/*
 * Copyright (c) 2020,2023, The Linux Foundation. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *	* Redistributions of source code must retain the above copyright
 *	  notice, this list of conditions and the following disclaimer.
 *	* Redistributions in binary form must reproduce the above
 *	  copyright notice, this list of conditions and the following
 *	  disclaimer in the documentation and/or other materials provided
 *	  with the distribution.
 *	* Neither the name of The Linux Foundation nor the names of its
 *	  contributors may be used to endorse or promote products derived
 *	  from this software without specific prior written permission.
 *
 *
 * THIS SOFTWARE IS PROVIDED "AS IS" AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN
 * IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/* Changes from Qualcomm Innovation Center are provided under the following license:

Copyright (c) 2023 Qualcomm Innovation Center, Inc. All rights reserved.
SPDX-License-Identifier: BSD-3-Clause-Clear */

#include <unistd.h>
#include <fcntl.h>
#include <cerrno>
#include <cstring>
#include <poll.h>
#include <sys/socket.h>
#include <linux/types.h>
#include <linux/netlink.h>
#include <android-base/logging.h>
#include <android-base/properties.h>
#include <android-base/stringprintf.h>

#include "thermalMonitor.h"
#include "Uevent.h"

#define UEVENT_BUF 1024

namespace aidl {
namespace android {
namespace hardware {
namespace thermal {

using parseCB = std::function<void(char *inp_buf, ssize_t len)>;
void thermal_monitor_uevent(const parseCB &parse_cb, int stopFd)
{
    struct pollfd pfd;
    char buf[UEVENT_BUF] = {0};
    int sz = 64*1024;
    struct sockaddr_nl nls;

    memset(&nls, 0, sizeof(nls));
    nls.nl_family = AF_NETLINK;
    nls.nl_pid = getpid();
    nls.nl_groups = 0xffffffff;

    pfd.events = POLLIN;
    pfd.fd = socket(PF_NETLINK, SOCK_DGRAM | SOCK_CLOEXEC,
            NETLINK_KOBJECT_UEVENT);
    if (pfd.fd < 0) {
        LOG(ERROR) << "socket creation error:" << errno << std::endl;
        return;
    }
    LOG(DEBUG) << "socket creation success" << std::endl;

    setsockopt(pfd.fd, SOL_SOCKET, SO_RCVBUF, &sz, sizeof(sz));
    if (bind(pfd.fd, (struct sockaddr *)&nls, sizeof(nls)) < 0) {
        close(pfd.fd);
        LOG(ERROR) << "socket bind failed:" << errno << std::endl;
        return;
    }
    LOG(DEBUG) << "Listening for uevent" << std::endl;

    struct pollfd fds[2] = {{pfd.fd, POLLIN, 0}, {stopFd, POLLIN, 0}};
    while (true) {
        ssize_t len;
        int err;

        err = poll(fds, 2, -1);
        if (err == -1) {
            if (errno == EINTR) continue;
            LOG(ERROR) << "Error in uevent poll.";
            break;
        }
        if (fds[1].revents) {
            LOG(INFO) << "Exiting uevent monitor" << std::endl;
            break;
        }
        if (fds[0].revents & (POLLHUP | POLLNVAL)) break;
        // recv reports recoverable netlink errors such as ENOBUFS.
        if (!(fds[0].revents & (POLLIN | POLLERR))) continue;
        len = recv(pfd.fd, buf, sizeof(buf) - 1, MSG_DONTWAIT);
        if (len == -1) {
            LOG(ERROR) << "uevent read failed:" << errno << std::endl;
            continue;
        }
        buf[len] = '\0';

        parse_cb(buf, len);
    }

    close(pfd.fd);
}

ThermalMonitor::ThermalMonitor(const ueventMonitorCB &inp_cb):
    cb(inp_cb)
{
}

ThermalMonitor::~ThermalMonitor()
{
    stop();
}

void ThermalMonitor::stop()
{
    if (!th.joinable()) return;
    const char wake = 1;
    while (write(stop_fds[1], &wake, sizeof(wake)) < 0 && errno == EINTR) {}
    th.join();
    close(stop_fds[0]);
    close(stop_fds[1]);
    stop_fds[0] = stop_fds[1] = -1;
}

void ThermalMonitor::start()
{
    if (th.joinable()) return;
    if (pipe(stop_fds) < 0) {
        LOG(ERROR) << "Unable to create thermal shutdown pipe: " << errno;
        return;
    }
    if (fcntl(stop_fds[0], F_SETFD, FD_CLOEXEC) < 0 ||
        fcntl(stop_fds[1], F_SETFD, FD_CLOEXEC) < 0) {
        close(stop_fds[0]);
        close(stop_fds[1]);
        stop_fds[0] = stop_fds[1] = -1;
        return;
    }
    try {
        th = std::thread(thermal_monitor_uevent,
            std::bind(&ThermalMonitor::parse_and_notify, this,
                std::placeholders::_1, std::placeholders::_2),
            stop_fds[0]);
    } catch (...) {
        close(stop_fds[0]);
        close(stop_fds[1]);
        stop_fds[0] = stop_fds[1] = -1;
        throw;
    }
}

void ThermalMonitor::parse_and_notify(char *inp_buf, ssize_t len)
{
    if (!inp_buf || len <= 0) return;
    const auto parsed = parseThermalUevent(
            std::string_view(inp_buf, static_cast<size_t>(len)));
    if (parsed) cb(parsed->first, parsed->second);
}

}  // namespace thermal
}  // namespace hardware
}  // namespace android
}  // namespace aidl
