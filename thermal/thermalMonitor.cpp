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
using pollCB = std::function<bool()>;

void thermal_monitor_uevent(const parseCB &parse_cb, const pollCB &stopPollCB)
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

    while (!stopPollCB()) {
        ssize_t len;
        int err;

        err = poll(&pfd, 1, -1);
        if (err == -1) {
            LOG(ERROR) << "Error in uevent poll.";
            break;
        }
        if (stopPollCB()) {
            LOG(INFO) << "Exiting uevent monitor" << std::endl;
            return;
        }
        len = recv(pfd.fd, buf, sizeof(buf) - 1, MSG_DONTWAIT);
        if (len == -1) {
            LOG(ERROR) << "uevent read failed:" << errno << std::endl;
            continue;
        }
        buf[len] = '\0';

        parse_cb(buf, len);
    }

    return;
}

ThermalMonitor::ThermalMonitor(const ueventMonitorCB &inp_cb):
    cb(inp_cb)
{
    monitor_shutdown = false;
}

ThermalMonitor::~ThermalMonitor()
{
    monitor_shutdown = true;
    th.join();
}

void ThermalMonitor::start()
{
    th = std::thread(thermal_monitor_uevent,
        std::bind(&ThermalMonitor::parse_and_notify, this,
            std::placeholders::_1, std::placeholders::_2),
        std::bind(&ThermalMonitor::stopPolling, this));
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
