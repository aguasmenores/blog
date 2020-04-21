#!/usr/bin/gawk -E
@load "filefuncs" # stat function.
@load "time" # gettimeofday

function assert(condition, string) {
    if (! condition) {
        printf("assertion failed: %s\n",
               string) > "/dev/stderr"
        _assert_exit = 1
        exit 1
    }
}

function match_ipv64(ip) {
    if (ip !~ SS REGEX_IPV64 SE) {
        return 0
    }
    return 1
}

function match_ipv4(ip) {
    if (ip !~ SS REGEX_IPV4 SE) {
        return 0
    }
    return 1
}

function match_ipv6(ip) {
    if (ip !~ SS REGEX_IPV6 SE) {
        return 0
    }
    return 1
}

function match_ip(ip) {
    if (ip !~ SS REGEX_IP SE) {
        return 0
    }
    return 1
}

function do_test(fun,set,wc) {
    n1 = split(set,test_set," ")
    n2 = split(wc,test_values," ")
    assert(n1==n2,"Unit test: set and values for "fun" have different length. "\
           "length(ip_set)=="n1 ", length(ip_wc)="n2)
    for (i=1;i<=length(test_set);i++) {
        res = @fun(tolower(test_set[i]))
        assert(res == test_values[i],
            "Unit test: test of "fun" with IP "test_set[i]" failed. "\
               "Returned: "res". Should be: "test_values[i]".")
    }
}

function unit_test() {
    ip_set_v4="0.0.0.0 127.0.0.1 255.255.255.255 256.254.253.252 "\
        "255.255.255.256 255.255.2555.252 255.255.25.252 "\
        "233.221.3"
    ip_wc_v4="1 1 1 0 0 0 1 0"
    fun="match_ipv4"
    do_test(fun,ip_set_v4,ip_wc_v4)
    
    ip_set_v6="fe80::e484:21:bfb3:9fc1 fz80:fd490::1 "\
        "::1 abCd:3040::1 ABCD::0 repeat::again::0 fe80::1%lo0"
    ip_wc_v6="1 0 1 1 1 0 1"
    fun="match_ipv6"
    do_test(fun,ip_set_v6,ip_wc_v6)

    ip_set_v64="2001:0DB8:0::0:1428:192.0.1.1 2001:0Db8::0:192.0.1.1 "  \
        "::ffff:127.0.0.1 ::127.0.0.1"
    ip_wc_v64="0 0 1 0"
    fun="match_ipv64"
    do_test(fun,ip_set_v64,ip_wc_v64)
    
    ip_set_all=ip_set_v4 " " ip_set_v6 " " ip_set_v64
    ip_wc_all=ip_wc_v4 " " ip_wc_v6 " " ip_wc_v64
    fun="match_ip"
    do_test(fun,ip_set_all,ip_wc_all)
}

function notify_users(msg,urgency) {
    which_cmd = "which > /dev/null " NOTIFY
    res = system(which_cmd)
    assert(res == 0, "Command " NOTIFY "is not available. Aborting.")
    if (length(urgency) == 0) urgency = "low"
    i = 1
    while (("who" | getline) > 0) {
        if ($0 ~ /[:alnum:]/) {
            n = split($0,disp_fields,"[[:space:]]+")
            ONLINE[i] = disp_fields[1]
            DISPLAYS[i] = disp_fields[2]
        }
    }
    close("who")
    for (u in ONLINE) {
        id_cmd = "id -u " ONLINE[u]
        id_cmd | getline uid
        disp = DISPLAYS[u]
        close(id_cmd)
        su_cmd = "su -c \"env DISPLAY="disp\
            " DBUS_SESSION_BUS_ADDRESS='unix:path=/run/user/"uid"/bus' " \
            NOTIFY " -u " urgency \
            " \\\"Actualització arxiu /etc/hosts\\\" "msg" \" " ONLINE[u]
        res = system(su_cmd)
    }
}

function fail() {
    res = system("/usr/bin/logger -p 'cron.info' "LOG_ID\
                 ": 'Update of hosts file failed. Please check that "\
                 "Internet is available and that /etc/hosts-original exists'" )
    notify_users(MSG_ERR,"critical")
    exit 1
}

BEGIN {
    BL_FILE="/tmp/hosts-zero"
    BL_URL="https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"
    MSG_INFO="\\\"El fitxer /etc/hosts ha estat actualitzat.\\\""
    MSG_ERR="\\\"No s'ha pogut actualitzar el fitxer /etc/hosts. "\
        "Consulta /var/syslog.\\\""
    NOTIFY="notify-send"
    LOG_ID="HOSTS UPDATE"
    WS="\\<"
    WE="\\>"
    SS="^"
    SE="$"
    IPV4_OCT=WS"(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])"WE
    IPV6_SEG=WS"[0-9a-f]{1,4}"WE
    REGEX_IPV4="(("IPV4_OCT"[.]){3}"IPV4_OCT")"
    REGEX_IPV6="((("IPV6_SEG":){7}"IPV6_SEG\
        "|("IPV6_SEG":){1,7}:"\
        "|("IPV6_SEG":){1,6}:"IPV6_SEG\
        "|("IPV6_SEG":){1,5}(:"IPV6_SEG"){1,2}"\
        "|("IPV6_SEG":){1,4}(:"IPV6_SEG"){1,3}"\
        "|("IPV6_SEG":){1,3}(:"IPV6_SEG"){1,4}"\
        "|("IPV6_SEG":){1,2}(:"IPV6_SEG"){1,5}"\
        "|"IPV6_SEG":(:"IPV6_SEG"){1,6})"\
        "|::"IPV6_SEG"(:"IPV6_SEG"){0,6}"\
        "|"IPV6_SEG"(:"IPV6_SEG"){0,6}::)(%[0-9a-z]+)?"

    REGEX_IPV64="((::(0{1,4}:){1,5}|(0{1,4}:){6}|((0{1,4}:){1,5}"       \
        "|::((0{1,4}:){1,4})?)[f]{4}:)"REGEX_IPV4")"

    REGEX_IP=SS"(" REGEX_IPV4 "|" REGEX_IPV6 "|" REGEX_IPV64 ")"SE

    REGEX_WHITELIST=SS"(0[.]0[.]0[.]0|127[.]0[.][01][.]1|255[.]255[.]255[.]255"\
        "|::[01]|f[ef]0[02]::[0-3]|fe80::[01]%[0-9a-z]+)"SE

    if (ARGC > 1) {
        if (ARGV[1] == "test") {
            unit_test()
            print "Tests passed successfully."
        }
        exit 0
    }
    
    if (stat("/etc/hosts-original",fstat)) fail()
    
    wget_cmd = "wget -O " BL_FILE " " BL_URL " 2> /dev/null"
    if (system(wget_cmd)) fail()

    STARTT = gettimeofday()
    FS="[[:space:][:cntrl:]]+"
    while ((getline < BL_FILE) > 0) {
        if ($0 ~ /^[^#[:cntrl:][:space:]]+/) {
            ip = tolower($1)
            if (ip !~ REGEX_IP && ip !~ REGEX_WHITELIST) {
                fail()
            }
        }
    }
    close(BL_FILE)
    ELAPSED = gettimeofday() - STARTT
    print "Elapsed time: " ELAPSED " s"
    while ((getline < "/etc/hosts-original") > 0) {
        print $0 > "/etc/hosts"
    }
    close("/etc/hosts-original")
    while ((getline < BL_FILE) > 0) {
        print $0 >> "/etc/hosts"
    }
    close(BL_FILE)
    rm_cmd = "rm " BL_FILE
    res = system(rm_cmd)
    log_cmd = system("/usr/bin/logger -p 'cron.info' "LOG_ID\
                 ": 'Hosts file updated with '"BL_URL)
    notify_users(MSG_INFO,"low")
    exit 0
}
END {
    if (_assert_exit)
        exit 1
}
