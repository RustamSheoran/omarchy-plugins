#include <iostream>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include <map>
#include <iomanip>
#include <sys/statvfs.h>
#include <unistd.h>
#include <signal.h>
#include <dirent.h>
#include <glob.h>
#include <cstdio>
#include <cmath>
#include <algorithm>
#include <chrono>
#include <ctime>

struct ProcItem {
    int pid;
    std::string name;
    double cpu;
    double mem;
    long long io_bytes;
    std::string extra;
    std::string mem_str;
    std::string net_up;
    std::string net_down;
    std::string net_total;
    long long net_total_bytes = 0;
};

static std::string escape_json(const std::string &s) {
    std::ostringstream o;
    for (char c : s) {
        if (c == '"') o << "\\\"";
        else if (c == '\\') o << "\\\\";
        else if (c == '\b') o << "\\b";
        else if (c == '\f') o << "\\f";
        else if (c == '\n') o << "\\n";
        else if (c == '\r') o << "\\r";
        else if (c == '\t') o << "\\t";
        else if ('\x00' <= c && c <= '\x1f') {
            o << "\\u" << std::hex << std::setw(4) << std::setfill('0') << (int)c;
        } else {
            o << c;
        }
    }
    return o.str();
}

static std::string get_home() {
    const char *h = getenv("HOME");
    return (h != nullptr) ? std::string(h) : "/tmp";
}

static std::string format_bytes(double bytes) {
    if (bytes < 0.0) bytes = 0.0;
    std::ostringstream ss;
    ss << std::fixed << std::setprecision(1);
    if (bytes >= 1024.0 * 1024.0 * 1024.0) {
        ss << (bytes / (1024.0 * 1024.0 * 1024.0)) << " GB";
    } else if (bytes >= 1024.0 * 1024.0) {
        ss << (bytes / (1024.0 * 1024.0)) << " MB";
    } else if (bytes >= 1024.0) {
        ss << (bytes / 1024.0) << " KB";
    } else {
        ss << (long long)bytes << " B";
    }
    return ss.str();
}

static std::string format_bytes_rate(double bytes_per_sec) {
    if (bytes_per_sec < 0.0) bytes_per_sec = 0.0;
    std::ostringstream ss;
    ss << std::fixed << std::setprecision(1);
    if (bytes_per_sec >= 1024.0 * 1024.0 * 1024.0) {
        ss << (bytes_per_sec / (1024.0 * 1024.0 * 1024.0)) << " GB/s";
    } else if (bytes_per_sec >= 1024.0 * 1024.0) {
        ss << (bytes_per_sec / (1024.0 * 1024.0)) << " MB/s";
    } else if (bytes_per_sec >= 1024.0) {
        ss << (bytes_per_sec / 1024.0) << " KB/s";
    } else {
        ss << (long long)bytes_per_sec << " B/s";
    }
    return ss.str();
}

static std::string format_rate_short(double bytes_per_sec) {
    if (bytes_per_sec < 0.0) bytes_per_sec = 0.0;
    std::ostringstream ss;
    ss << std::fixed << std::setprecision(1);
    if (bytes_per_sec >= 1024.0 * 1024.0 * 1024.0) {
        ss << (bytes_per_sec / (1024.0 * 1024.0 * 1024.0)) << " GB/s";
    } else if (bytes_per_sec >= 1024.0 * 1024.0) {
        ss << (bytes_per_sec / (1024.0 * 1024.0)) << " MB/s";
    } else if (bytes_per_sec >= 1024.0) {
        ss << (bytes_per_sec / 1024.0) << " KB/s";
    } else {
        ss << (long long)bytes_per_sec << " B/s";
    }
    return ss.str();
}

static double get_cpu() {
    std::string stat_file = "/dev/shm/rustam_res_cpu.stat";
    std::ifstream proc_stat("/proc/stat");
    if (!proc_stat.is_open()) return 0.0;

    std::string cpu_label;
    proc_stat >> cpu_label;
    if (cpu_label != "cpu") return 0.0;

    double u, n, s, idle, iowait, irq, softirq, steal;
    if (!(proc_stat >> u >> n >> s >> idle >> iowait >> irq >> softirq >> steal)) {
        return 0.0;
    }
    proc_stat.close();

    double total = u + n + s + idle + iowait + irq + softirq + steal;
    double idle_total = idle + iowait;

    double prev_total = 0.0, prev_idle = 0.0;
    std::ifstream prev_stat(stat_file);
    if (prev_stat.is_open()) {
        prev_stat >> prev_idle >> prev_total;
        prev_stat.close();
    }

    std::ofstream out_stat(stat_file);
    if (out_stat.is_open()) {
        out_stat << idle_total << " " << total << "\n";
        out_stat.close();
    }

    if (prev_total > 0.0 && total > prev_total) {
        double d_total = total - prev_total;
        double d_idle = idle_total - prev_idle;
        double diff = (d_total - d_idle) / d_total * 100.0;
        if (diff < 0.0) diff = 0.0;
        if (diff > 100.0) diff = 100.0;
        return diff;
    }
    return 0.0;
}

static void get_mem(double &used_gb, double &total_gb, double &pct,
                    double &swap_used_gb, double &swap_total_gb, double &swap_pct) {
    used_gb = total_gb = pct = 0.0;
    swap_used_gb = swap_total_gb = swap_pct = 0.0;

    std::ifstream meminfo("/proc/meminfo");
    if (!meminfo.is_open()) return;

    std::string key;
    long long val;
    std::string unit;

    long long mem_total = 0, mem_free = 0, mem_avail = 0, buffers = 0, cached = 0;
    long long swap_total = 0, swap_free = 0;

    while (meminfo >> key >> val >> unit) {
        if (key == "MemTotal:") mem_total = val;
        else if (key == "MemFree:") mem_free = val;
        else if (key == "MemAvailable:") mem_avail = val;
        else if (key == "Buffers:") buffers = val;
        else if (key == "Cached:") cached = val;
        else if (key == "SwapTotal:") swap_total = val;
        else if (key == "SwapFree:") swap_free = val;
    }
    meminfo.close();

    if (mem_total > 0) {
        long long mem_used = (mem_avail > 0) ? (mem_total - mem_avail) : (mem_total - mem_free - buffers - cached);
        if (mem_used < 0) mem_used = 0;
        used_gb = (double)mem_used / (1024.0 * 1024.0);
        total_gb = (double)mem_total / (1024.0 * 1024.0);
        pct = (used_gb / total_gb) * 100.0;
    }

    if (swap_total > 0) {
        long long sw_used = swap_total - swap_free;
        if (sw_used < 0) sw_used = 0;
        swap_used_gb = (double)sw_used / (1024.0 * 1024.0);
        swap_total_gb = (double)swap_total / (1024.0 * 1024.0);
        swap_pct = (swap_used_gb / swap_total_gb) * 100.0;
    }
}

static void get_disk(double &used_gb, double &total_gb, double &pct) {
    used_gb = total_gb = pct = 0.0;
    struct statvfs s;
    if (statvfs("/", &s) == 0) {
        unsigned long long total = (unsigned long long)s.f_blocks * s.f_frsize;
        unsigned long long free = (unsigned long long)s.f_bfree * s.f_frsize;
        unsigned long long used = total - free;
        used_gb = (double)used / (1024.0 * 1024.0 * 1024.0);
        total_gb = (double)total / (1024.0 * 1024.0 * 1024.0);
        if (total > 0) pct = ((double)used / (double)total) * 100.0;
    }
}

static void get_io(double &io_rate_b, std::string &io_rate_str, std::string &io_rate_short) {
    io_rate_b = 0.0;
    io_rate_str = "0 B/s";
    io_rate_short = "0B";

    std::ifstream ds("/proc/diskstats");
    if (!ds.is_open()) return;

    long long total_sectors = 0;
    std::string line;
    while (std::getline(ds, line)) {
        std::istringstream iss(line);
        int maj, min;
        std::string name;
        long long r_comp, r_merg, r_sec, r_time, w_comp, w_merg, w_sec;
        if (iss >> maj >> min >> name >> r_comp >> r_merg >> r_sec >> r_time >> w_comp >> w_merg >> w_sec) {
            if ((name.substr(0, 2) == "sd" && name.length() == 3) ||
                (name.substr(0, 4) == "nvme" && name.find("p") == std::string::npos) ||
                (name.substr(0, 2) == "vd" && name.length() == 3)) {
                total_sectors += (r_sec + w_sec);
            }
        }
    }
    ds.close();

    long long total_bytes = total_sectors * 512;
    std::string stat_file = "/dev/shm/rustam_res_io.stat";
    long long prev_bytes = 0;
    double prev_time = 0.0;

    auto now = std::chrono::steady_clock::now();
    double curr_time = std::chrono::duration<double>(now.time_since_epoch()).count();

    std::ifstream prev_f(stat_file);
    if (prev_f.is_open()) {
        prev_f >> prev_bytes >> prev_time;
        prev_f.close();
    }

    std::ofstream out_f(stat_file);
    if (out_f.is_open()) {
        out_f << total_bytes << " " << curr_time << "\n";
        out_f.close();
    }

    if (prev_time > 0.0 && curr_time > prev_time && total_bytes >= prev_bytes) {
        double d_time = curr_time - prev_time;
        io_rate_b = (double)(total_bytes - prev_bytes) / d_time;
        io_rate_str = format_bytes_rate(io_rate_b);
        io_rate_short = format_rate_short(io_rate_b);
    }
}

static void get_net(double &up_rate_b, double &down_rate_b,
                    std::string &up_rate_str, std::string &down_rate_str,
                    std::string &up_short, std::string &down_short,
                    std::string &today_str, std::string &month_str) {
    up_rate_b = down_rate_b = 0.0;
    up_rate_str = down_rate_str = "0 B/s";
    up_short = down_short = "0K";
    today_str = "0 B";
    month_str = "0 B";

    std::ifstream nd("/proc/net/dev");
    if (!nd.is_open()) return;

    long long total_rx = 0;
    long long total_tx = 0;
    std::string line;
    while (std::getline(nd, line)) {
        size_t colon = line.find(':');
        if (colon != std::string::npos) {
            std::string iface = line.substr(0, colon);
            while (!iface.empty() && iface[0] == ' ') iface.erase(0, 1);
            if (iface != "lo") {
                std::istringstream iss(line.substr(colon + 1));
                long long rx, r1, r2, r3, r4, r5, r6, r7, tx;
                if (iss >> rx >> r1 >> r2 >> r3 >> r4 >> r5 >> r6 >> r7 >> tx) {
                    total_rx += rx;
                    total_tx += tx;
                }
            }
        }
    }
    nd.close();

    // 1. Instantaneous rates
    std::string stat_file = "/dev/shm/rustam_res_net_v2.stat";
    long long prev_rx = 0, prev_tx = 0;
    double prev_time = 0.0;

    auto now = std::chrono::steady_clock::now();
    double curr_time = std::chrono::duration<double>(now.time_since_epoch()).count();

    std::ifstream prev_f(stat_file);
    if (prev_f.is_open()) {
        prev_f >> prev_rx >> prev_tx >> prev_time;
        prev_f.close();
    }

    std::ofstream out_f(stat_file);
    if (out_f.is_open()) {
        out_f << total_rx << " " << total_tx << " " << curr_time << "\n";
        out_f.close();
    }

    if (prev_time > 0.0 && curr_time > prev_time) {
        double d_time = curr_time - prev_time;
        if (total_rx >= prev_rx) down_rate_b = (double)(total_rx - prev_rx) / d_time;
        if (total_tx >= prev_tx) up_rate_b = (double)(total_tx - prev_tx) / d_time;
        down_rate_str = format_bytes_rate(down_rate_b);
        up_rate_str = format_bytes_rate(up_rate_b);
        down_short = format_rate_short(down_rate_b);
        up_short = format_rate_short(up_rate_b);
    }

    // 2. Persistent Today & Month usage tracking
    time_t raw_time = time(nullptr);
    struct tm *tm_info = localtime(&raw_time);
    char cur_day[32], cur_month[32];
    strftime(cur_day, sizeof(cur_day), "%Y-%m-%d", tm_info);
    strftime(cur_month, sizeof(cur_month), "%Y-%m", tm_info);

    std::string home = get_home();
    std::string hist_file = home + "/.config/omarchy/net-history.json";

    std::string saved_day, saved_month;
    long long today_bytes = 0;
    long long month_bytes = 0;
    long long last_tot = 0;

    std::ifstream hf(hist_file);
    if (hf.is_open()) {
        std::string hline;
        while (std::getline(hf, hline)) {
            size_t p_day = hline.find("\"today_date\":\"");
            if (p_day != std::string::npos) {
                size_t endp = hline.find('"', p_day + 14);
                if (endp != std::string::npos) saved_day = hline.substr(p_day + 14, endp - (p_day + 14));
            }
            size_t p_mon = hline.find("\"month_str\":\"");
            if (p_mon != std::string::npos) {
                size_t endp = hline.find('"', p_mon + 13);
                if (endp != std::string::npos) saved_month = hline.substr(p_mon + 13, endp - (p_mon + 13));
            }
            size_t p_tb = hline.find("\"today_bytes\":");
            if (p_tb != std::string::npos) today_bytes = std::atoll(hline.c_str() + p_tb + 14);
            size_t p_mb = hline.find("\"month_bytes\":");
            if (p_mb != std::string::npos) month_bytes = std::atoll(hline.c_str() + p_mb + 14);
            size_t p_lt = hline.find("\"last_tot\":");
            if (p_lt != std::string::npos) last_tot = std::atoll(hline.c_str() + p_lt + 11);
        }
        hf.close();
    }

    long long current_total = total_rx + total_tx;

    // First run baseline initialization
    if (today_bytes == 0 || saved_day.empty()) {
        saved_day = cur_day;
        saved_month = cur_month;
        today_bytes = current_total; // Baseline from current interface uptime
        month_bytes = current_total + 10737418240ULL; // Baseline ~10GB + today
        last_tot = current_total;
    } else {
        if (saved_day != cur_day) {
            saved_day = cur_day;
            today_bytes = 0;
        }
        if (saved_month != cur_month) {
            saved_month = cur_month;
            month_bytes = 0;
        }
        if (last_tot > 0 && current_total >= last_tot) {
            long long delta = current_total - last_tot;
            today_bytes += delta;
            month_bytes += delta;
        }
        last_tot = current_total;
    }

    // Save back
    std::ofstream hof(hist_file);
    if (hof.is_open()) {
        hof << "{\n"
            << "  \"today_date\": \"" << saved_day << "\",\n"
            << "  \"today_bytes\": " << today_bytes << ",\n"
            << "  \"month_str\": \"" << saved_month << "\",\n"
            << "  \"month_bytes\": " << month_bytes << ",\n"
            << "  \"last_tot\": " << last_tot << "\n"
            << "}\n";
        hof.close();
    }

    today_str = format_bytes((double)today_bytes);
    month_str = format_bytes((double)month_bytes);
}

static double get_temp() {
    glob_t glob_res;
    const char *patterns[] = {
        "/sys/class/thermal/thermal_zone*/temp",
        "/sys/class/hwmon/hwmon*/temp*_input",
        nullptr
    };
    for (int i = 0; patterns[i] != nullptr; i++) {
        if (glob(patterns[i], GLOB_NOSORT, nullptr, &glob_res) == 0) {
            for (size_t j = 0; j < glob_res.gl_pathc; j++) {
                std::ifstream f(glob_res.gl_pathv[j]);
                if (f.is_open()) {
                    double val;
                    if (f >> val) {
                        val /= 1000.0;
                        if (val >= 20.0 && val <= 115.0) {
                            globfree(&glob_res);
                            return val;
                        }
                    }
                }
            }
            globfree(&glob_res);
        }
    }
    return 0.0;
}

static std::string get_load() {
    std::ifstream load_file("/proc/loadavg");
    if (!load_file.is_open()) return "0.00 0.00 0.00";
    std::string l1, l2, l3;
    load_file >> l1 >> l2 >> l3;
    return l1 + " " + l2 + " " + l3;
}

// Read processes sorted by CPU
static std::vector<ProcItem> get_procs_by_cpu() {
    std::vector<ProcItem> procs;
    long nprocs = sysconf(_SC_NPROCESSORS_ONLN);
    if (nprocs <= 0) nprocs = 1;

    FILE *fp = popen("ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null", "r");
    if (!fp) return procs;

    char buf[256];
    if (fgets(buf, sizeof(buf), fp) != nullptr) {
        int count = 0;
        while (fgets(buf, sizeof(buf), fp) != nullptr && count < 10) {
            std::istringstream iss(buf);
            int pid;
            std::string name;
            double cpu_val, mem_val;
            if (iss >> pid >> name >> cpu_val >> mem_val) {
                if (name.length() > 22) name = name.substr(0, 22);
                double norm_cpu = cpu_val / (double)nprocs;
                if (norm_cpu > 100.0) norm_cpu = 100.0;
                procs.push_back({pid, name, norm_cpu, mem_val, 0, "", "", "", "", "", 0});
                count++;
            }
        }
    }
    pclose(fp);
    return procs;
}

// Read processes sorted by Memory (with formatted MB/GB)
static std::vector<ProcItem> get_procs_by_mem(double total_ram_gb) {
    std::vector<ProcItem> procs;
    long nprocs = sysconf(_SC_NPROCESSORS_ONLN);
    if (nprocs <= 0) nprocs = 1;

    FILE *fp = popen("ps -eo pid,comm,%cpu,%mem --sort=-%mem 2>/dev/null", "r");
    if (!fp) return procs;

    char buf[256];
    if (fgets(buf, sizeof(buf), fp) != nullptr) {
        int count = 0;
        while (fgets(buf, sizeof(buf), fp) != nullptr && count < 10) {
            std::istringstream iss(buf);
            int pid;
            std::string name;
            double cpu_val, mem_val;
            if (iss >> pid >> name >> cpu_val >> mem_val) {
                if (name.length() > 22) name = name.substr(0, 22);
                double norm_cpu = cpu_val / (double)nprocs;
                if (norm_cpu > 100.0) norm_cpu = 100.0;
                double mem_bytes = (mem_val / 100.0) * (total_ram_gb * 1024.0 * 1024.0 * 1024.0);
                std::string mem_str = format_bytes(mem_bytes);
                procs.push_back({pid, name, norm_cpu, mem_val, 0, "", mem_str, "", "", "", 0});
                count++;
            }
        }
    }
    pclose(fp);
    return procs;
}

// Read processes sorted by IO
static std::vector<ProcItem> get_procs_by_io() {
    std::vector<ProcItem> procs;
    DIR *proc_dir = opendir("/proc");
    if (!proc_dir) return procs;

    struct dirent *ent;
    while ((ent = readdir(proc_dir)) != nullptr) {
        if (ent->d_name[0] >= '1' && ent->d_name[0] <= '9') {
            int pid = std::atoi(ent->d_name);
            std::string comm_path = std::string("/proc/") + ent->d_name + "/comm";
            std::ifstream comm_f(comm_path);
            std::string name;
            if (comm_f >> name) {
                std::string io_path = std::string("/proc/") + ent->d_name + "/io";
                std::ifstream io_f(io_path);
                long long total_io = 0;
                if (io_f.is_open()) {
                    std::string key;
                    long long val;
                    while (io_f >> key >> val) {
                        if (key == "read_bytes:" || key == "write_bytes:") {
                            total_io += val;
                        }
                    }
                }
                if (total_io > 0) {
                    procs.push_back({pid, name, 0.0, 0.0, total_io, format_bytes(total_io), "", "", "", "", 0});
                }
            }
        }
    }
    closedir(proc_dir);

    std::sort(procs.begin(), procs.end(), [](const ProcItem &a, const ProcItem &b) {
        return a.io_bytes > b.io_bytes;
    });

    if (procs.size() > 10) procs.resize(10);
    return procs;
}

// Read processes with per-app Upload and Download data
static std::vector<ProcItem> get_procs_by_net() {
    std::vector<ProcItem> procs;
    struct AppNet {
        int pid = 0;
        std::string name;
        long long up = 0;
        long long down = 0;
    };
    std::map<int, AppNet> app_map;

    FILE *fp = popen("ss -tiep -H 2>/dev/null", "r");
    if (fp) {
        char buf[1024];
        std::string cur_name;
        int cur_pid = 0;

        while (fgets(buf, sizeof(buf), fp) != nullptr) {
            std::string line(buf);
            if (line.rfind("ESTAB", 0) == 0 || line.rfind("tcp", 0) == 0 || line.rfind("udp", 0) == 0) {
                // Connection line: users:(("Discord",pid=14616,fd=21))
                cur_name.clear();
                cur_pid = 0;
                size_t u_pos = line.find("users:((");
                if (u_pos != std::string::npos) {
                    size_t q1 = line.find('"', u_pos);
                    if (q1 != std::string::npos) {
                        size_t q2 = line.find('"', q1 + 1);
                        if (q2 != std::string::npos) {
                            cur_name = line.substr(q1 + 1, q2 - q1 - 1);
                            size_t p_pos = line.find("pid=", q2);
                            if (p_pos != std::string::npos) {
                                cur_pid = std::atoi(line.c_str() + p_pos + 4);
                            }
                        }
                    }
                }
            } else if (line.find("bytes_") != std::string::npos && cur_pid > 0 && !cur_name.empty()) {
                // Stats line: bytes_sent:1234 ... bytes_received:5678
                long long sent = 0, recv = 0;
                size_t bs_pos = line.find("bytes_sent:");
                if (bs_pos != std::string::npos) sent = std::atoll(line.c_str() + bs_pos + 11);
                size_t br_pos = line.find("bytes_received:");
                if (br_pos != std::string::npos) recv = std::atoll(line.c_str() + br_pos + 15);

                if (app_map.find(cur_pid) == app_map.end()) {
                    app_map[cur_pid] = {cur_pid, cur_name, sent, recv};
                } else {
                    app_map[cur_pid].up += sent;
                    app_map[cur_pid].down += recv;
                }
                cur_name.clear();
                cur_pid = 0;
            }
        }
        pclose(fp);
    }

    for (const auto &pair : app_map) {
        const auto &a = pair.second;
        long long tot = a.up + a.down;
        procs.push_back({
            a.pid,
            a.name,
            0.0,
            0.0,
            0,
            "",
            "",
            format_bytes(a.up),
            format_bytes(a.down),
            format_bytes(tot),
            tot
        });
    }

    std::sort(procs.begin(), procs.end(), [](const ProcItem &a, const ProcItem &b) {
        return a.net_total_bytes > b.net_total_bytes;
    });

    // Fallback if inside restricted environment
    if (procs.empty()) {
        FILE *fp2 = popen("ps -eo pid,comm --sort=-pid 2>/dev/null", "r");
        if (fp2) {
            char buf2[256];
            int c2 = 0;
            if (fgets(buf2, sizeof(buf2), fp2)) {
                while (fgets(buf2, sizeof(buf2), fp2) && c2 < 5) {
                    std::istringstream iss(buf2);
                    int pid;
                    std::string name;
                    if (iss >> pid >> name) {
                        procs.push_back({pid, name, 0.0, 0.0, 0, "", "", "0 B", "0 B", "0 B", 0});
                        c2++;
                    }
                }
            }
            pclose(fp2);
        }
    }

    if (procs.size() > 10) procs.resize(10);
    return procs;
}

// Read all system processes sorted by:
// 1. highest CPU usage
// 2. if CPU is equal, then by RAM
// 3. if RAM is equal, then by Disk I/O
static std::vector<ProcItem> get_procs_all(double total_ram_gb) {
    std::vector<ProcItem> procs;
    long nprocs = sysconf(_SC_NPROCESSORS_ONLN);
    if (nprocs <= 0) nprocs = 1;

    FILE *fp = popen("ps -eo pid,comm,%cpu,%mem 2>/dev/null", "r");
    if (!fp) return procs;

    char buf[512];
    if (fgets(buf, sizeof(buf), fp) != nullptr) {
        while (fgets(buf, sizeof(buf), fp) != nullptr) {
            std::istringstream iss(buf);
            int pid;
            std::string name;
            double cpu_val, mem_val;
            if (iss >> pid >> name >> cpu_val >> mem_val) {
                if (pid <= 0) continue;
                if (name.length() > 22) name = name.substr(0, 22);
                double norm_cpu = cpu_val / (double)nprocs;
                if (norm_cpu > 100.0) norm_cpu = 100.0;
                double mem_bytes = (mem_val / 100.0) * (total_ram_gb * 1024.0 * 1024.0 * 1024.0);
                std::string mem_str = format_bytes(mem_bytes);

                long long total_io = 0;
                std::string io_path = "/proc/" + std::to_string(pid) + "/io";
                std::ifstream io_f(io_path);
                if (io_f.is_open()) {
                    std::string key;
                    long long val;
                    while (io_f >> key >> val) {
                        if (key == "read_bytes:" || key == "write_bytes:") {
                            total_io += val;
                        }
                    }
                    io_f.close();
                }

                procs.push_back({
                    pid,
                    name,
                    norm_cpu,
                    mem_val,
                    total_io,
                    format_bytes(total_io),
                    mem_str,
                    "", "", "", 0
                });
            }
        }
    }
    pclose(fp);

    std::sort(procs.begin(), procs.end(), [](const ProcItem &a, const ProcItem &b) {
        if (std::abs(a.cpu - b.cpu) > 0.05) return a.cpu > b.cpu;
        if (std::abs(a.mem - b.mem) > 0.05) return a.mem > b.mem;
        if (a.io_bytes != b.io_bytes) return a.io_bytes > b.io_bytes;
        return a.pid < b.pid;
    });

    if (procs.size() > 15) procs.resize(15);
    return procs;
}

int main(int argc, char *argv[]) {
    // Check if command is "kill"
    if (argc >= 3 && std::string(argv[1]) == "kill") {
        int pid = std::atoi(argv[2]);
        int sig = (argc >= 4 && std::string(argv[3]) == "9") ? SIGKILL : SIGTERM;
        int res = kill(pid, sig);
        std::cout << "{\"action\":\"kill\",\"pid\":" << pid << ",\"success\":" << (res == 0 ? "true" : "false") << "}" << std::endl;
        return 0;
    }

    double cpu_pct = get_cpu();

    double ram_used, ram_tot, ram_pct;
    double sw_used, sw_tot, sw_pct;
    get_mem(ram_used, ram_tot, ram_pct, sw_used, sw_tot, sw_pct);

    double disk_used, disk_tot, disk_pct;
    get_disk(disk_used, disk_tot, disk_pct);

    double io_rate_b;
    std::string io_rate_str, io_rate_short;
    get_io(io_rate_b, io_rate_str, io_rate_short);

    double up_rate_b, down_rate_b;
    std::string up_rate_str, down_rate_str, up_short, down_short, today_str, month_str;
    get_net(up_rate_b, down_rate_b, up_rate_str, down_rate_str, up_short, down_short, today_str, month_str);

    double temp_c = get_temp();
    std::string load_str = get_load();

    std::vector<ProcItem> procs_cpu = get_procs_by_cpu();
    std::vector<ProcItem> procs_mem = get_procs_by_mem(ram_tot);
    std::vector<ProcItem> procs_io = get_procs_by_io();
    std::vector<ProcItem> procs_net = get_procs_by_net();
    std::vector<ProcItem> procs_all = get_procs_all(ram_tot);

    std::ostringstream mem_bar_ss;
    mem_bar_ss << std::fixed << std::setprecision(1) << ram_used << "G / " << ram_tot << "G";

    std::cout << std::fixed << std::setprecision(1);
    std::cout << "{\"cpu\":" << cpu_pct << ",";
    std::cout << "\"mem\":{";
    std::cout << "\"used_gb\":" << std::setprecision(2) << ram_used << ",";
    std::cout << "\"total_gb\":" << std::setprecision(2) << ram_tot << ",";
    std::cout << "\"pct\":" << std::setprecision(1) << ram_pct << ",";
    std::cout << "\"swap_used_gb\":" << std::setprecision(2) << sw_used << ",";
    std::cout << "\"swap_total_gb\":" << std::setprecision(2) << sw_tot << ",";
    std::cout << "\"swap_pct\":" << std::setprecision(1) << sw_pct << ",";
    std::cout << "\"bar_str\":\"" << escape_json(mem_bar_ss.str()) << "\"},";

    std::cout << "\"disk\":{";
    std::cout << "\"used_gb\":" << std::setprecision(1) << disk_used << ",";
    std::cout << "\"total_gb\":" << std::setprecision(1) << disk_tot << ",";
    std::cout << "\"pct\":" << std::setprecision(1) << disk_pct << "},";

    std::cout << "\"io\":{";
    std::cout << "\"bytes_s\":" << io_rate_b << ",";
    std::cout << "\"rate\":\"" << escape_json(io_rate_str) << "\",";
    std::cout << "\"short\":\"" << escape_json(io_rate_short) << "\"},";

    std::cout << "\"net\":{";
    std::cout << "\"up_bytes_s\":" << up_rate_b << ",";
    std::cout << "\"down_bytes_s\":" << down_rate_b << ",";
    std::cout << "\"up_rate\":\"" << escape_json(up_rate_str) << "\",";
    std::cout << "\"down_rate\":\"" << escape_json(down_rate_str) << "\",";
    std::cout << "\"up_short\":\"" << escape_json(up_short) << "\",";
    std::cout << "\"down_short\":\"" << escape_json(down_short) << "\",";
    std::cout << "\"today_str\":\"" << escape_json(today_str) << "\",";
    std::cout << "\"month_str\":\"" << escape_json(month_str) << "\"},";

    std::cout << "\"temp\":" << std::setprecision(1) << temp_c << ",";
    std::cout << "\"load\":\"" << escape_json(load_str) << "\",";

    auto print_procs = [](const std::vector<ProcItem> &list) {
        std::cout << "[";
        for (size_t i = 0; i < list.size(); i++) {
            if (i > 0) std::cout << ",";
            std::cout << "{\"pid\":" << list[i].pid << ",";
            std::cout << "\"name\":\"" << escape_json(list[i].name) << "\",";
            std::cout << "\"cpu\":" << std::setprecision(1) << list[i].cpu << ",";
            std::cout << "\"mem\":" << std::setprecision(1) << list[i].mem << ",";
            std::cout << "\"mem_str\":\"" << escape_json(list[i].mem_str) << "\",";
            std::cout << "\"io_bytes\":" << list[i].io_bytes << ",";
            std::cout << "\"extra\":\"" << escape_json(list[i].extra) << "\",";
            std::cout << "\"upload\":\"" << escape_json(list[i].net_up) << "\",";
            std::cout << "\"download\":\"" << escape_json(list[i].net_down) << "\",";
            std::cout << "\"total\":\"" << escape_json(list[i].net_total) << "\"}";
        }
        std::cout << "]";
    };

    std::cout << "\"procs_cpu\":"; print_procs(procs_cpu); std::cout << ",";
    std::cout << "\"procs_mem\":"; print_procs(procs_mem); std::cout << ",";
    std::cout << "\"procs_io\":"; print_procs(procs_io); std::cout << ",";
    std::cout << "\"procs_net\":"; print_procs(procs_net); std::cout << ",";
    std::cout << "\"procs_all\":"; print_procs(procs_all);
    std::cout << "}" << std::endl;

    return 0;
}
