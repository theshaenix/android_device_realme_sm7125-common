#!/usr/bin/env python3
"""Exercise production monitor lifetime using a socketpair in place of netlink."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
header = (root/'thermalMonitor.h').read_text().replace(
    '#include <aidl/android/hardware/thermal/BnThermal.h>', '#include <functional>\n#include <string>')
source = (root/'thermalMonitor.cpp').read_text()
source = '\n'.join(line for line in source.splitlines()
                   if not line.startswith('#include <android-base/')
                   and not line.startswith('#include <linux/'))
source = source.replace('socket(PF_NETLINK,', 'test_socket(PF_NETLINK,').replace(
    'bind(pfd.fd,', 'test_bind(pfd.fd,')
prelude = r'''
#include <cassert>
#include <atomic>
#include <chrono>
#include <cstring>
#include <iostream>
#include <sys/socket.h>
#include <unistd.h>
#define LOG(level) std::cerr
#ifndef SOCK_CLOEXEC
#define SOCK_CLOEXEC 0
#endif
#define PF_NETLINK 16
#define AF_NETLINK 16
#define NETLINK_KOBJECT_UEVENT 15
struct sockaddr_nl { unsigned short nl_family; unsigned nl_pid,nl_groups; };
static std::atomic<int> opened{0};
static int peer=-1, monitor_fd=-1;
static bool fail_socket=false;
static int test_socket(int, int, int) {
 if(fail_socket) { errno=EMFILE; return -1; }
 int pair[2]; assert(socketpair(AF_UNIX,SOCK_DGRAM,0,pair)==0);
 peer=pair[1]; monitor_fd=pair[0]; opened++; return pair[0];
}
static int test_bind(int, const sockaddr*, socklen_t) { return 0; }
'''
main = r'''
using namespace aidl::android::hardware::thermal;
int main() {
 { ThermalMonitor never_started([](auto,auto){}); }
 for(int i=0;i<10;i++) {
  opened=0;
  { ThermalMonitor monitor([](auto,auto){}); monitor.start();
    auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(1);
    while(!opened && std::chrono::steady_clock::now()<deadline) std::this_thread::yield();
    assert(opened); monitor.start(); monitor.stop(); monitor.stop(); }
  assert(fcntl(monitor_fd,F_GETFD)==-1 && errno==EBADF);
  close(peer);
 }
 fail_socket=true;
 { ThermalMonitor failed([](auto,auto){}); failed.start(); }
 std::cout << "PASS: unstarted, blocked and failed-start monitor teardown\n";
}
'''
with tempfile.TemporaryDirectory() as tmp:
    path = pathlib.Path(tmp)
    (path/'thermalMonitor.h').write_text(header)
    (path/'Uevent.h').write_text((root/'Uevent.h').read_text())
    (path/'test.cpp').write_text(prelude+source+main)
    subprocess.run(['clang++','-std=c++17','-pthread','-fsanitize=address,undefined',
                    str(path/'test.cpp'),'-o',str(path/'test')],check=True)
    subprocess.run([str(path/'test')],check=True,timeout=5)
