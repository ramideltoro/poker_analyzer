// Copyright (C) 2026 Live Card Reader contributors.
// SPDX-License-Identifier: AGPL-3.0-or-later
// A local JSON stdin/stdout front end to Wataru Inariba's postflop-solver.
use postflop_solver::*;
use serde::{Deserialize, Serialize};
use std::{io::{self, Read}, time::Instant};

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    protocol: u32,
    hole: Vec<String>, board: Vec<String>, oop_range: String, ip_range: String,
    hero_ip: bool, pot_cents: i32, stack_cents: i32, facing_bet_cents: i32,
    rake_percent: f64, rake_cap_cents: i32, max_iterations: u32,
    target_gap_percent: f32, seconds: u32,
}
#[derive(Debug, Serialize)]
struct Choice { action: String, amount_cents: i32, frequency: f32, ev_cents: f32 }
#[derive(Debug, Serialize)]
struct ResultData {
    protocol: u32, engine: &'static str, iterations: u32, elapsed_seconds: f64,
    exploitability_cents: f32, gap_percent: f32, converged: bool, memory_bytes: u64, compressed: bool,
    equity: f32, ev_cents: f32, choices: Vec<Choice>,
}
fn solve_request(r: &Request) -> Result<ResultData, String> {
    let start = Instant::now();
    if r.protocol != 1 || r.hole.len() != 2 || !(3..=5).contains(&r.board.len()) {
        return Err("Use protocol 1, two hole cards and a flop, turn or river.".into());
    }
    if !(1..=1_000_000).contains(&r.pot_cents) || !(1..=1_000_000).contains(&r.stack_cents)
        || r.stack_cents as f64 / r.pot_cents as f64 > 20.0
        || !(0..=r.stack_cents).contains(&r.facing_bet_cents)
        || !(10..=2000).contains(&r.max_iterations) || !(1..=60).contains(&r.seconds)
        || !r.target_gap_percent.is_finite() || !(0.01..=5.0).contains(&r.target_gap_percent)
        || !r.rake_percent.is_finite() || !(0.0..=10.0).contains(&r.rake_percent)
        || !(0..=1_000_000).contains(&r.rake_cap_cents) {
        return Err("Invalid money, SPR (maximum 20), convergence, time or rake settings.".into());
    }
    if r.oop_range.len() > 12000 || r.ip_range.len() > 12000 { return Err("Range is too long.".into()); }
    let mut seen = std::collections::HashSet::new();
    for c in r.hole.iter().chain(r.board.iter()) {
        let card = card_from_str(c)?;
        if !seen.insert(card) { return Err("Duplicate card in hole cards / board.".into()); }
    }
    let hole = (card_from_str(&r.hole[0])?, card_from_str(&r.hole[1])?);
    let ranges: [Range; 2] = [r.oop_range.parse()?, r.ip_range.parse()?];
    let hero = usize::from(r.hero_ip);
    if ranges[hero].get_weight_by_cards(hole.0, hole.1) <= 0.0 {
        return Err("Your hole cards are absent from your range. Use your full plausible range, not just your known hand.".into());
    }
    // Check the villain has combinations compatible with the actual hero hand as well as the board.
    let mask = seen.iter().fold(0u64, |m, &c| m | (1u64 << c));
    if ranges[hero ^ 1].get_hands_weights(mask).1.iter().all(|w| *w <= 0.0) {
        return Err("Opponent range has no combinations compatible with these cards.".into());
    }
    let cards = CardConfig {
        range: ranges,
        flop: flop_from_str(&r.board[..3].join(""))?,
        turn: if r.board.len() >= 4 { card_from_str(&r.board[3])? } else { NOT_DEALT },
        river: if r.board.len() == 5 { card_from_str(&r.board[4])? } else { NOT_DEALT },
    };
    // Deliberately small, explicit action abstraction. Never claim a full-size no-limit solution.
    let sizes = BetSizeOptions::try_from(("50%", "100%"))?;
    let config = TreeConfig {
        initial_state: match r.board.len() { 3 => BoardState::Flop, 4 => BoardState::Turn, _ => BoardState::River },
        starting_pot: r.pot_cents, effective_stack: r.stack_cents,
        rake_rate: r.rake_percent / 100.0, rake_cap: r.rake_cap_cents as f64,
        flop_bet_sizes: [sizes.clone(), sizes.clone()], turn_bet_sizes: [sizes.clone(), sizes.clone()],
        river_bet_sizes: [sizes.clone(), sizes], turn_donk_sizes: None, river_donk_sizes: None,
        add_allin_threshold: 0.0, force_allin_threshold: 0.0, merging_threshold: 0.0,
    };
    let mut tree = ActionTree::new(config)?;
    let mut path = Vec::new();
    if (r.hero_ip && r.facing_bet_cents == 0) || (!r.hero_ip && r.facing_bet_cents > 0) { path.push(Action::Check); }
    if r.facing_bet_cents > 0 {
        let a = if r.facing_bet_cents == r.stack_cents { Action::AllIn(r.facing_bet_cents) } else { Action::Bet(r.facing_bet_cents) };
        path.push(a);
        tree.apply_history(&path[..path.len()-1])?;
        if !tree.available_actions().contains(&a) { tree.add_line(&path)?; }
        tree.back_to_root();
    }
    let mut game = PostFlopGame::with_config(cards, tree)?;
    let (full_memory, compressed_memory) = game.memory_usage();
    let compressed=full_memory>256*1024*1024;
    let memory=if compressed { compressed_memory } else { full_memory };
    if memory > 512 * 1024 * 1024 { return Err(format!("Tree needs {:.0} MiB strategy storage; limit is 512 MiB. Use narrower plausible ranges or study a later street.", memory as f64 / 1048576.0)); }
    game.allocate_memory(compressed);
    let target = r.pot_cents as f32 * r.target_gap_percent / 100.0;
    let mut gap;
    let mut iterations = 0;
    for i in 0..r.max_iterations {
        if start.elapsed().as_secs_f64() >= r.seconds as f64 { break; }
        solve_step(&game, i);
        iterations = i + 1;
        if iterations % 10 == 0 || iterations == r.max_iterations {
            gap = compute_exploitability(&game);
            if gap <= target { break; }
        }
    }
    // Always measure the final profile; a budget-limited result must not inherit an older gap.
    gap = compute_exploitability(&game);
    finalize(&mut game);
    for a in path {
        let i = game.available_actions().iter().position(|x| *x == a).ok_or("Requested node is absent from the tree")?;
        game.play(i);
    }
    if game.is_terminal_node() || game.is_chance_node() || game.current_player() != hero { return Err("Not a hero decision node.".into()); }
    game.cache_normalized_weights();
    let hands = game.private_cards(hero);
    let hand_index = hands.iter().position(|&(a,b)| (a == hole.0 && b == hole.1) || (a == hole.1 && b == hole.0)).ok_or("Hero hand is absent")?;
    // An equilibrium may never reach the requested line with this hand. Undefined off-path
    // strategies must never become a real-time recommendation.
    if game.normalized_weights(hero)[hand_index] <= 1e-10 { return Err("This hand has zero reach at the requested node in the solved strategy. Choose a different range or node.".into()); }
    let n = hands.len();
    let strategy = game.strategy();
    let values = game.expected_values_detail(hero);
    let choices: Vec<_> = game.available_actions().iter().enumerate().map(|(i, a)| {
        let (name, amount) = match a {
            Action::Fold => ("fold", 0), Action::Check => ("check", 0), Action::Call => ("call", r.facing_bet_cents),
            Action::Bet(v) => ("bet", *v), Action::Raise(v) => ("raise", *v),
            Action::AllIn(v) => (if r.facing_bet_cents == 0 { "bet" } else { "raise" }, *v),
            _ => unreachable!(),
        };
        Choice { action: name.into(), amount_cents: amount, frequency: strategy[i*n+hand_index], ev_cents: values[i*n+hand_index] }
    }).collect();
    let result = ResultData {
        protocol: 1, engine: "postflop-solver / DCFR", iterations, elapsed_seconds: start.elapsed().as_secs_f64(),
        exploitability_cents: gap, gap_percent: gap / r.pot_cents as f32 * 100.0,
        converged: iterations > 0 && gap <= target, memory_bytes: memory, compressed,
        equity: game.equity(hero)[hand_index], ev_cents: game.expected_values(hero)[hand_index], choices,
    };
    if !result.equity.is_finite() || !gap.is_finite() || !result.ev_cents.is_finite()
        || result.choices.iter().any(|c| !c.frequency.is_finite() || !c.ev_cents.is_finite()) { return Err("Solver produced non-finite values.".into()); }
    Ok(result)
}
fn main() {
    let pool = rayon::ThreadPoolBuilder::new().num_threads(2).build().unwrap();
    let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let mut input = String::new();
        io::stdin().take(65537).read_to_string(&mut input).map_err(|_| "Cannot read request".to_owned())?;
        if input.len() > 65536 { return Err("Request exceeds 64 KiB.".into()); }
        let request: Request = serde_json::from_str(&input).map_err(|e| format!("Invalid request: {e}"))?;
        pool.install(|| solve_request(&request))
    }));
    let output = match result {
        Ok(Ok(value)) => serde_json::to_value(value).unwrap(),
        Ok(Err(error)) => serde_json::json!({"error": error}),
        Err(_) => serde_json::json!({"error": "Solver stopped while building or evaluating this tree."}),
    };
    println!("{}", output);
}

#[cfg(test)]
mod tests {
    use super::*;
    fn request() -> Request {
        serde_json::from_value(serde_json::json!({
            "protocol":1,"hole":["As","Kd"],"board":["2c","3d","4h","5s","9c"],
            "oop_range":"AsKd","ip_range":"KcKh","hero_ip":false,"pot_cents":200,"stack_cents":100,
            "facing_bet_cents":100,"rake_percent":0,"rake_cap_cents":0,"max_iterations":100,
            "target_gap_percent":0.5,"seconds":5
        })).unwrap()
    }
    #[test]
    fn river_nuts_facing_allin_has_exact_incremental_ev() {
        let r=solve_request(&request()).unwrap();
        let call=r.choices.iter().find(|x| x.action=="call").unwrap();
        assert!((call.ev_cents-300.0).abs()<0.01,"{:?}",r);
        assert!(call.frequency>0.99);assert!((r.equity-1.0).abs()<0.0001);assert!(r.converged);
        assert!(!r.choices.iter().any(|x| x.action=="raise"));
    }
    #[test]
    fn river_loser_folds_and_call_loses_only_extra_price() {
        let mut q=request();q.hole=vec!["Kc".into(),"Kh".into()];q.oop_range="KcKh".into();q.ip_range="AsKd".into();
        let r=solve_request(&q).unwrap();
        assert!(r.choices.iter().find(|x| x.action=="fold").unwrap().frequency>0.99);
        assert!((r.choices.iter().find(|x| x.action=="call").unwrap().ev_cents+100.0).abs()<0.01);
    }
    #[test]
    fn split_pot_and_rake_have_exact_ev() {
        let mut q=request();q.board=vec!["As","Ks","Qs","Js","Ts"].into_iter().map(str::to_owned).collect();
        q.hole=vec!["2c".into(),"3d".into()];q.oop_range="3d2c".into();q.ip_range="5d4c".into();
        q.facing_bet_cents=0;let r=solve_request(&q).unwrap();assert!((r.equity-0.5).abs()<0.0001);
        assert!((r.ev_cents-100.0).abs()<0.01);
        q.rake_percent=5.0;q.rake_cap_cents=100;q.hero_ip=true;q.facing_bet_cents=100;q.oop_range="5d4c".into();q.ip_range="3d2c".into();
        let r=solve_request(&q).unwrap();assert!((r.choices.iter().find(|x| x.action=="call").unwrap().ev_cents-90.0).abs()<0.01,"{:?}",r);
    }
    #[test]
    fn invalid_or_impossible_cards_and_ranges_are_rejected() {
        let mut q=request();q.board[0]="As".into();assert!(solve_request(&q).unwrap_err().contains("Duplicate"));
        let mut q=request();q.oop_range="QQ".into();assert!(solve_request(&q).unwrap_err().contains("absent"));
        let mut q=request();q.ip_range="AsAh".into();assert!(solve_request(&q).unwrap_err().contains("compatible"));
        let mut q=request();q.facing_bet_cents=101;assert!(solve_request(&q).is_err());
    }
    #[test]
    fn ip_after_check_and_exact_offgrid_bet_return_normalized_strategies() {
        for facing in [0,37] {
            let mut q=request();q.hero_ip=true;q.hole=vec!["Kc".into(),"Kh".into()];
            q.oop_range="AA,KK,QQ,AsKd,7c6c".into();q.ip_range="KK,QQ,JJ,7d6d".into();
            q.stack_cents=300;q.facing_bet_cents=facing;q.max_iterations=500;
            let r=solve_request(&q).unwrap();assert!((r.choices.iter().map(|c| c.frequency).sum::<f32>()-1.0).abs()<1e-5);
            assert!(r.choices.iter().all(|c| c.ev_cents.is_finite()));
            if facing>0 { assert!(r.choices.iter().any(|c| c.action=="call" && c.amount_cents==37)); }
            else { assert!(r.choices.iter().any(|c| c.action=="check")); }
        }
    }
}
