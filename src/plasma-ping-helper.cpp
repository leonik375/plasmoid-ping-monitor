/*
 * plasma-ping-helper — send one ICMP echo request and report the result as JSON.
 *
 * Written for the Ping Monitor plasmoid, which cannot call into C++ directly
 * and would otherwise have to scrape the output of /usr/bin/ping. Printing
 * JSON keeps the widget free of locale dependent text parsing.
 *
 * SPDX-FileCopyrightText: 2026 leonik <leonik.eut@gmail.com>
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#include "icmplib.h"

#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>

namespace {

const char *USAGE =
    "Usage: plasma-ping-helper <host> [options]\n"
    "\n"
    "  -c, --count <n>      echo requests to send (default 1)\n"
    "  -w, --timeout <ms>   time to wait for each reply (default 2000)\n"
    "  -s, --size <bytes>   payload size (default 64)\n"
    "  -t, --ttl <n>        outgoing TTL / hop limit (default 255)\n"
    "  -q, --sequence <n>   first ICMP sequence number (default 1)\n"
    "  -4                   resolve to IPv4 only\n"
    "  -6                   resolve to IPv6 only\n"
    "  -h, --help           show this text\n"
    "\n"
    "Prints a single JSON object on stdout. Exit status is 0 when the host\n"
    "replied at least once, 1 when it did not, and 2 on a usage or system\n"
    "error.\n";

// Outcome of a whole run, which may be several echo requests.
struct Summary {
    icmplib::PingResult best {};   // the most informative reply seen
    bool haveBest = false;
    unsigned sent = 0;
    unsigned received = 0;
    double total = 0.0;
    double min = 0.0;
    double max = 0.0;
};

// Success beats an error reply, which beats no reply at all, so a single lost
// packet does not mask the fact that the host is up.
int rank(icmplib::PingResponseType type)
{
    switch (type) {
    case icmplib::PingResponseType::Success:      return 5;
    case icmplib::PingResponseType::Unsupported:  return 4;
    case icmplib::PingResponseType::Unreachable:  return 3;
    case icmplib::PingResponseType::TimeExceeded: return 2;
    case icmplib::PingResponseType::Timeout:      return 1;
    case icmplib::PingResponseType::Failure:      break;
    }
    return 0;
}

std::string jsonEscape(const std::string &in)
{
    std::string out;
    out.reserve(in.size() + 8);
    for (unsigned char c : in) {
        switch (c) {
        case '"':  out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\b': out += "\\b"; break;
        case '\f': out += "\\f"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default:
            if (c < 0x20) {
                char buf[7];
                std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                out += buf;
            } else {
                out += static_cast<char>(c);
            }
        }
    }
    return out;
}

// A definitive answer: the widget can render this without further context.
int emitResult(const Summary &summary, const std::string &requested)
{
    const icmplib::PingResult &result = summary.best;
    const char *status = "failure";
    bool replied = false;   // the target itself answered
    bool answered = false;  // some host answered, possibly an intermediate one

    switch (result.response) {
    case icmplib::PingResponseType::Success:
        status = "success";      replied = true; answered = true; break;
    case icmplib::PingResponseType::Unsupported:
        status = "unsupported";  replied = true; answered = true; break;
    case icmplib::PingResponseType::Unreachable:
        status = "unreachable";  answered = true; break;
    case icmplib::PingResponseType::TimeExceeded:
        status = "timeexceeded"; answered = true; break;
    case icmplib::PingResponseType::Timeout:
        status = "timeout";      break;
    case icmplib::PingResponseType::Failure:
        status = "failure";      break;
    }

    const unsigned lost = summary.sent - summary.received;
    const double loss = summary.sent > 0
        ? (100.0 * static_cast<double>(lost) / static_cast<double>(summary.sent))
        : 0.0;

    std::cout << "{\"status\":\"" << status << "\""
              << ",\"host\":\"" << jsonEscape(requested) << "\""
              << ",\"sent\":" << summary.sent
              << ",\"received\":" << summary.received
              << ",\"loss\":" << loss;

    if (summary.received > 0) {
        std::cout << ",\"rtt\":" << (summary.total / summary.received)
                  << ",\"rtt_min\":" << summary.min
                  << ",\"rtt_max\":" << summary.max;
    }
    // Nothing answered on a timeout or a local failure, so the address and the
    // code carry no information and are left out rather than reported as zero.
    if (answered) {
        std::cout << ",\"address\":\"" << jsonEscape(std::string(result.address)) << "\""
                  << ",\"code\":" << static_cast<unsigned>(result.code)
                  << ",\"ttl\":" << static_cast<unsigned>(result.ttl);
    }
    std::cout << "}" << std::endl;

    return replied ? 0 : 1;
}

int emitError(const std::string &message)
{
    std::cout << "{\"status\":\"error\",\"message\":\"" << jsonEscape(message) << "\"}"
              << std::endl;
    return 2;
}

bool parseUnsigned(const char *text, unsigned long &out)
{
    if (!text || !*text) {
        return false;
    }
    char *end = nullptr;
    const unsigned long value = std::strtoul(text, &end, 10);
    if (end == text || (end && *end != '\0')) {
        return false;
    }
    out = value;
    return true;
}

} // namespace

int main(int argc, char **argv)
{
    std::string host;
    unsigned long timeout = 2000;
    unsigned long size = ICMPLIB_PING_DATA_SIZE;
    unsigned long ttl = 255;
    unsigned long sequence = 1;
    unsigned long count = 1;
    auto family = icmplib::IPAddress::Type::Unknown;

    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        const bool hasValue = (i + 1 < argc);

        if (arg == "-h" || arg == "--help") {
            std::cerr << USAGE;
            return 0;
        } else if (arg == "-4") {
            family = icmplib::IPAddress::Type::IPv4;
        } else if (arg == "-6") {
            family = icmplib::IPAddress::Type::IPv6;
        } else if ((arg == "-c" || arg == "--count") && hasValue) {
            if (!parseUnsigned(argv[++i], count) || count == 0 || count > 64) {
                return emitError("invalid count");
            }
        } else if ((arg == "-w" || arg == "--timeout") && hasValue) {
            if (!parseUnsigned(argv[++i], timeout) || timeout == 0 || timeout > 600000) {
                return emitError("invalid timeout");
            }
        } else if ((arg == "-s" || arg == "--size") && hasValue) {
            if (!parseUnsigned(argv[++i], size) || size > ICMPLIB_MAX_PING_DATA_SIZE) {
                return emitError("invalid payload size");
            }
        } else if ((arg == "-t" || arg == "--ttl") && hasValue) {
            if (!parseUnsigned(argv[++i], ttl) || ttl == 0 || ttl > 255) {
                return emitError("invalid ttl");
            }
        } else if ((arg == "-q" || arg == "--sequence") && hasValue) {
            if (!parseUnsigned(argv[++i], sequence) || sequence > 65535) {
                return emitError("invalid sequence");
            }
        } else if (!arg.empty() && arg[0] == '-') {
            return emitError("unknown option " + arg);
        } else if (host.empty()) {
            host = arg;
        } else {
            return emitError("more than one host given");
        }
    }

    if (host.empty()) {
        std::cerr << USAGE;
        return emitError("no host given");
    }

    try {
        // Literal addresses are taken as they are, anything else goes through
        // DNS. Both happen here, and a bad host name throws.
        const icmplib::IPAddress target(host, family);

        Summary summary;
        for (unsigned long i = 0; i < count; ++i) {
            const icmplib::PingResult result = icmplib::Ping(
                target,
                static_cast<unsigned>(timeout),
                static_cast<uint16_t>((sequence + i) & 0xffff),
                static_cast<uint8_t>(ttl),
                static_cast<uint16_t>(size));

            summary.sent += 1;
            if (result.response == icmplib::PingResponseType::Success) {
                if (summary.received == 0 || result.delay < summary.min) {
                    summary.min = result.delay;
                }
                if (summary.received == 0 || result.delay > summary.max) {
                    summary.max = result.delay;
                }
                summary.received += 1;
                summary.total += result.delay;
            }
            if (!summary.haveBest || rank(result.response) > rank(summary.best.response)) {
                summary.best = result;
                summary.haveBest = true;
            }
        }

        return emitResult(summary, host);
    } catch (const std::exception &e) {
        return emitError(e.what());
    } catch (...) {
        return emitError("unknown failure");
    }
}
