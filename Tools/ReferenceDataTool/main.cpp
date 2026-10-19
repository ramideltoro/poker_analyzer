// Offline importer. No network, player names, hand IDs or wagering data in output.
#include "PokerEvaluator.h"
#include <algorithm>
#include <array>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <vector>
#include <unordered_set>
using namespace std;
using Count = unsigned long long;
struct Stats { Count known=0,river=0; array<Count,9> categories{}; };
map<string,Stats> classes;
Count hands=0,flops=0,rivers=0,excluded=0,invalid=0,files=0,duplicateIDs=0,conflictingDuplicates=0,rawHands=0,rawHandHQ=0,quarantinedRecords=0,conflictingGroups=0;
map<string,vector<string>> seen;
map<string,unordered_set<string>> duplicates,conflicting;
map<string,map<string,Count>> occurrences;
map<string,map<string,vector<string>>> firstActions;
map<string,Count> sources;
int card(string s) { if(s.size()!=2) return -1; auto r=string("23456789TJQKA").find(s[0]),u=string("cdhs").find(s[1]); return r==string::npos||u==string::npos?-1:int(r*4+u); }
vector<int> cards(string s) { vector<int> v; for(size_t i=0;i+1<s.size();i+=2) { int c=card(s.substr(i,2)); if(c<0) return {}; v.push_back(c); } return v; }
string handClass(vector<int> c) { int a=c[0]/4,b=c[1]/4; if(a<b) swap(a,b); string s; s+=string("23456789TJQKA")[a]; s+=string("23456789TJQKA")[b]; if(a!=b) s+=c[0]%4==c[1]%4?'s':'o'; return s; }
int category(int v) { return v<=10?8:v<=166?7:v<=322?6:v<=1599?5:v<=1609?4:v<=2467?3:v<=3325?2:v<=6185?1:0; }
struct Record { bool nt=false; string handID; string venue; vector<string> actions; };
void tally(const vector<string> &actions,const string &source) {
 ++hands; ++sources[source]; vector<int> board; map<int,vector<int>> hole;
 for(auto &a:actions) { istringstream ss(a); string p,action,v; ss>>p>>action>>v;
  if(p=="d"&&action=="dh") { string value; ss>>value; if(v.size()>1) hole[stoi(v.substr(1))]=cards(value); }
  else if(p=="d"&&action=="db") { auto c=cards(v); board.insert(board.end(),c.begin(),c.end()); }
  else if(p.size()>1&&p[0]=='p'&&action=="sm") hole[stoi(p.substr(1))]=cards(v);
 }
 if(board.size()>=3) ++flops; if(board.size()==5) ++rivers;
 for(auto &h:hole) { if(h.second.size()!=2) continue; auto all=h.second; all.insert(all.end(),board.begin(),board.end()); if(set<int>(all.begin(),all.end()).size()!=all.size()||board.size()>5) {++invalid;continue;}
  auto &s=classes[handClass(h.second)]; ++s.known;
  if(board.size()==5) {++s.river; ++s.categories[category(evaluate_7cards(all[0],all[1],all[2],all[3],all[4],all[5],all[6]))];}
 }
}
void consume(Record &r,const string &source) {
 if(r.actions.empty()) return;
 if(!r.nt) { ++excluded; return; }
 ++rawHands;if(source=="HandHQ 2009")++rawHandHQ;
 if(source=="HandHQ 2009" && duplicates[r.venue].count(r.handID)) {
  auto &count=occurrences[r.venue][r.handID];++count;
  if(count==1) firstActions[r.venue][r.handID]=r.actions;
  else {
   ++duplicateIDs;
   if(firstActions[r.venue][r.handID]!=r.actions) {++conflictingDuplicates;conflicting[r.venue].insert(r.handID);}
  }
  return;
 }
 tally(r.actions,source);
}
vector<string> quotes(string line) { vector<string> v; char q=0; string s; for(char c:line) {if(!q&&(c=='\''||c=='"')) {q=c;s.clear();} else if(q&&c==q) {v.push_back(s);q=0;} else if(q) s+=c;} return v; }
string uncomment(const string &line) {
 char q=0;
 for(size_t i=0;i<line.size();++i) {
  char c=line[i];
  if(!q&&c=='#')return line.substr(0,i);
  if(!q&&(c=='\''||c=='"'))q=c;else if(q&&c==q)q=0;
 }
 return line;
}
string identifier(const string &line) {
 auto quoted=quotes(line);if(!quoted.empty())return quoted[0];
 string value=uncomment(line).substr(6);auto first=value.find_first_not_of(" \t\r");
 if(first==string::npos)return "";auto last=value.find_last_not_of(" \t\r");return value.substr(first,last-first+1);
}
int main(int argc,char **argv) {
 if(argc!=4) {cerr<<"usage: poker-reference-tool PHH_ROOT UCI_ROOT OUTPUT_JSON\n";return 2;}
 vector<filesystem::path> inputFiles;
 for(auto &e:filesystem::recursive_directory_iterator(argv[1])) if(e.is_regular_file()&&(e.path().extension()==".phh"||e.path().extension()==".phhs"))inputFiles.push_back(e.path());
 sort(inputFiles.begin(),inputFiles.end());
 // First pass profiles venue-scoped IDs. Keep only repeated keys for the main import.
 for(auto &inputPath:inputFiles) {
  auto ext=inputPath.extension(); if((ext!=".phh"&&ext!=".phhs")||inputPath.string().find("handhq")==string::npos) continue;
  ifstream f(inputPath);string line,venue,id;bool nt=false;
  auto flush=[&] {if(nt&&!id.empty())seen[venue].push_back(id);};
  while(getline(f,line)) {
   if(line.rfind("variant =",0)==0) {flush();id.clear();venue.clear();auto q=quotes(line);nt=!q.empty()&&q[0]=="NT";}
   else if(line.rfind("hand =",0)==0) {id=identifier(line);}
   else if(line.rfind("venue =",0)==0) {auto q=quotes(line);if(!q.empty())venue=q[0];}
  } flush();
 }
 for(auto &v:seen) {sort(v.second.begin(),v.second.end());for(size_t i=1;i<v.second.size();++i)if(v.second[i]==v.second[i-1])duplicates[v.first].insert(v.second[i]);}
 seen.clear();cerr<<"Duplicate audit complete; aggregating unique Hold'em records\n";
 for(auto &inputPath:inputFiles)
 { auto ext=inputPath.extension(); if(ext!=".phh"&&ext!=".phhs") continue; ++files;
  auto path=inputPath.string(); string source=path.find("handhq")!=string::npos?"HandHQ 2009":path.find("pluribus")!=string::npos?"Pluribus":"Other PHH";
  ifstream f(inputPath); string line; Record r;
  while(getline(f,line)) { if(line.rfind("variant =",0)==0) {consume(r,source);r=Record{};auto q=quotes(line);r.nt=!q.empty()&&q[0]=="NT";} else if(line.rfind("actions =",0)==0) {string actions=uncomment(line);while(actions.find(']')==string::npos && getline(f,line))actions+=" "+uncomment(line);r.actions=quotes(actions);} else if(line.rfind("hand =",0)==0) {r.handID=identifier(line);} else if(line.rfind("venue =",0)==0) {auto q=quotes(line);if(!q.empty())r.venue=q[0];} }
  consume(r,source); if(files%500==0) cerr<<files<<" files, "<<hands<<" Hold'em records\n";
 }
 // Ambiguous same-ID histories are quarantined as a group; exact repeats count once.
 for(auto &venue:firstActions)for(auto &entry:venue.second) {
  if(conflicting[venue.first].count(entry.first)) {++conflictingGroups;quarantinedRecords+=occurrences[venue.first][entry.first];}
  else tally(entry.second,"HandHQ 2009");
 }
 Count uci=0
,mismatch=0;array<Count,10> labels{};
 for(auto &e:filesystem::directory_iterator(argv[2])) {if(e.path().extension()!=".data") continue; ifstream f(e.path());string line;
  while(getline(f,line)) {replace(line.begin(),line.end(),',',' ');istringstream ss(line);vector<int> c;int suit,rank,label;bool ok=true; for(int i=0;i<5;++i) {if(!(ss>>suit>>rank)||suit<1||suit>4||rank<1||rank>13) {ok=false;break;} int mapSuit[]={0,2,3,1,0};c.push_back(((rank==1?14:rank)-2)*4+mapSuit[suit]);}
   if(!ok||!(ss>>label)||label<0||label>9||set<int>(c.begin(),c.end()).size()!=5) {++mismatch;continue;}
   ++uci;++labels[label];int score=evaluate_5cards(c[0],c[1],c[2],c[3],c[4]);int actual=score==1?9:category(score);if(actual!=label) ++mismatch;
  }
 }
 ofstream o(argv[3]);o<<"{\n\"schemaVersion\":1,\"hands\":"<<hands<<",\"rawHands\":"<<rawHands<<",\"rawHandHQ\":"<<rawHandHQ<<",\"quarantinedRecords\":"<<quarantinedRecords<<",\"conflictingGroups\":"<<conflictingGroups<<",\"flops\":"<<flops<<",\"rivers\":"<<rivers<<",\"files\":"<<files<<",\"excludedVariants\":"<<excluded<<",\"duplicateHandHQIDs\":"<<duplicateIDs<<",\"conflictingDuplicateActions\":"<<conflictingDuplicates<<",\"invalidRevealedSamples\":"<<invalid<<",\"uciRows\":"<<uci<<",\"uciMismatches\":"<<mismatch<<",\"sources\":{";
 bool comma=false;for(auto &s:sources) {if(comma)o<<",";comma=true;o<<"\""<<s.first<<"\":"<<s.second;}o<<"},\"classes\":{";comma=false;
 for(auto &p:classes) {if(comma)o<<",";comma=true;auto &s=p.second;o<<"\n\""<<p.first<<"\":{\"known\":"<<s.known<<",\"river\":"<<s.river<<",\"categories\":[";for(int i=0;i<9;++i){if(i)o<<",";o<<s.categories[i];}o<<"]}";}
 o<<"}\n}\n"; cerr<<"Complete: "<<hands<<" Hold'em hands; "<<uci<<" UCI rows; "<<mismatch<<" mismatches; "<<duplicateIDs<<" duplicate HandHQ IDs\n";
 return mismatch?1:0;
}
