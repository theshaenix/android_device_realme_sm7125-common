#!/usr/bin/env python3
"""Run production file/temperature reads and SoC retry loop without Android IPC."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
common = (root/'thermalCommon.cpp').read_text()
reader = common[common.index('static int readLineFromFile('):
                common.index('\nint ThermalCommon::readFromFile(')]
temperature = common[common.index('int ThermalCommon::read_temperature('):
                     common.index('\nvoid ThermalCommon::initThreshold(')]
cooling = common[common.index('int ThermalCommon::read_cdev_state('):common.index('\nint ThermalCommon::estimateSeverity(')]
config = (root/'thermalConfig.cpp').read_text()
start = config.index('        soc_id = 0;', config.index('ThermalConfig::ThermalConfig()'))
retry = config[start:config.index('\n        auto range =', start)]
prelude = r'''
#include <algorithm>
#include <cassert>
#include <cerrno>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <string>
#include <string_view>
#define LOG(level) std::cerr
#define MAX_LENGTH 256
#define MAX_PATH 1024
#define RETRY_CT 3
static std::string temperatureFormat;
#define TEMPERATURE_FILE_FORMAT temperatureFormat.c_str()
#define CDEV_CUR_STATE_PATH temperatureFormat.c_str()
struct therm_sensor { int tzn=0; int mulFactor=1000; struct {float value=42; std::string name="test";} t; };
struct therm_cdev {int cdevn=0; struct {int value=7; std::string name="cooling";} c;};
struct ThermalCommon { int read_temperature(therm_sensor&); int read_cdev_state(therm_cdev&); };
struct FakeReader {
 int calls=0, failures=0; bool fail_platform=false, bad_soc=false;
 int readFromFile(const char* path,std::string& out) {
  ++calls; if(calls<=failures) return -EIO;
  if(fail_platform && std::string(path)=="platform") {fail_platform=false; return -EIO;}
  if(bad_soc && std::string(path)=="soc") {bad_soc=false; out="bad"; return 3;}
  out="443"; return 3;
 }
};
static void identify(FakeReader& cmnInst,int& soc_id) {
 const char *socIDPath="soc", *hwPlatformPath="platform";
 std::string soc_val,hw_platform; int ct=0; bool read_ok=false;
'''
main = r'''
int main(int argc,char** argv) {
 assert(argc==2); std::string base=argv[1]; temperatureFormat=base+"/%d";
 std::string out="stale";
 assert(readLineFromFile(base+"/absent",out)<0 && out.empty());
 assert(readLineFromFile(base,out)<0 && out.empty());
 { std::ofstream file(base+"/0"); file<<"invalid\n"; }
 therm_sensor sensor; ThermalCommon common; therm_cdev cooling;
 assert(common.read_cdev_state(cooling)<0 && cooling.c.value==7);
 assert(common.read_temperature(sensor)<0 && sensor.t.value==42);
 { std::ofstream file(base+"/0"); file<<"123bad\n"; }
 assert(common.read_temperature(sensor)<0 && sensor.t.value==42);
 { std::ofstream file(base+"/0"); file<<"45000\n"; }
 assert(common.read_temperature(sensor)>0 && sensor.t.value==45);
 { std::ofstream file(base+"/0"); file<<"0\n"; }
 assert(common.read_cdev_state(cooling)==0 && cooling.c.value==0);
 { std::ofstream file(base+"/0"); }
 assert(common.read_temperature(sensor)<0);
 for(int failures: {1,2,99}) {
  FakeReader reader; reader.failures=failures; int soc=-1; identify(reader,soc);
  if(failures<3) assert(soc==443 && reader.calls==failures+2);
  else assert(soc==0 && reader.calls==3);
 }
 for(bool bad: {false,true}) {
  FakeReader reader; reader.fail_platform=!bad; reader.bad_soc=bad;
  int soc=0; identify(reader,soc); assert(soc==443 && reader.calls==4);
 }
 std::cout<<"PASS: missing/empty/malformed/valid reads and bounded SoC retries\n";
}
'''
with tempfile.TemporaryDirectory() as tmp:
    path = pathlib.Path(tmp)
    (path/'test.cpp').write_text(prelude+retry+'\n}\n'+reader+temperature+cooling+main)
    subprocess.run(['clang++','-std=c++17','-fsanitize=address,undefined',
                    str(path/'test.cpp'),'-o',str(path/'test')],check=True)
    subprocess.run([str(path/'test'),tmp],check=True)
