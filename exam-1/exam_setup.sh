#!/bin/bash
#===============================================================================
#  Linux Practical Exam - ENVIRONMENT SETUP SCRIPT
#  Target platform: CentOS Stream 10 (also works on RHEL/Rocky/Alma 8-10, CentOS 7).
#  Run as root INSIDE the exam VM before the exam starts.
#
#  BEFORE running this script, attach two spare virtual disks to the VirtualBox VM:
#      VirtualBox -> VM Settings -> Storage -> Controller SATA -> Add Hard Disk
#      Disk 1: 2 GB   (used for Question 15 - partition + ext4)
#      Disk 2: 3 GB   (used for Question 16 - LVM, grows to 1 GiB)
#  They normally appear as /dev/sdb and /dev/sdc. The script detects them
#  automatically; if none are found it falls back to loop-backed image files.
#
#  Usage:  ./exam_setup.sh                 # prepare the exam environment
#          ./exam_setup.sh --reset         # wipe previous exam artifacts, then prepare
#          ./exam_setup.sh --yes           # do not ask before erasing the spare disks
#          EXAM_DISK1=/dev/sdb EXAM_DISK2=/dev/sdc ./exam_setup.sh   # force devices
#===============================================================================

EXAM_HOME="/etc/exam"
EXPECTED_DIR="${EXAM_HOME}/expected"
ENV_FILE="${EXAM_HOME}/exam.env"
DISK_DIR="/var/exam-disks"
DATA="/exam-data"

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; BLU='\033[0;34m'; NC='\033[0m'
info()  { echo -e "${BLU}[INFO]${NC} $*"; }
ok()    { echo -e "${GRN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YLW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }

#------------------------------------------------------------------------------
# 0. Pre-flight
#------------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    fail "This script must be run as root."
    exit 1
fi

if command -v dnf >/dev/null 2>&1; then PKG="dnf"; else PKG="yum"; fi
info "Package manager detected: ${PKG}"

#------------------------------------------------------------------------------
# 1. Optional reset of a previous exam run
#------------------------------------------------------------------------------
reset_env() {
    info "Resetting previous exam environment..."

    # Un-mount candidate mountpoints
    for mp in /mnt/examdata /mnt/lvdata; do
        umount -f "$mp" 2>/dev/null
    done
    sed -i '\#/mnt/examdata#d;\#/mnt/lvdata#d' /etc/fstab 2>/dev/null

    # Remove candidate LVM objects
    if command -v vgs >/dev/null 2>&1; then
        lvremove -f /dev/vgexam 2>/dev/null
        vgremove -f vgexam      2>/dev/null
    fi

    # Stop / remove exam units
    for u in exam-rogue.service examlog.service; do
        systemctl stop "$u"    2>/dev/null
        systemctl disable "$u" 2>/dev/null
        systemctl unmask "$u"  2>/dev/null
        rm -f "/etc/systemd/system/${u}" "/usr/lib/systemd/system/${u}"
    done
    systemctl daemon-reload 2>/dev/null

    # Remove exam users / groups
    for u in alice bob carol dev01; do userdel -r "$u" 2>/dev/null; done
    for g in sysadmins auditors; do groupdel "$g" 2>/dev/null; done

    # Candidate work areas + source data
    rm -rf /opt/reports /opt/projects /opt/backups "$DATA" "$EXAM_HOME"
    rm -f  /etc/sudoers.d/sysadmins /usr/local/bin/examlog.sh \
           /usr/local/bin/exam-rogue.sh /var/log/examlog.log
    crontab -r -u alice 2>/dev/null

    # Wipe candidate work from the spare disks (real-disk mode)
    if [ -f "$ENV_FILE" ]; then
        . "$ENV_FILE" 2>/dev/null
        if [ "$EXAM_DISK_MODE" = "real" ]; then
            for d in "$EXAM_DISK1" "$EXAM_DISK2"; do
                [ -b "$d" ] || continue
                wipefs -a "$d" >/dev/null 2>&1
            done
        fi
    fi

    # Detach loop devices and delete backing files
    for img in "${DISK_DIR}"/disk*.img; do
        [ -e "$img" ] || continue
        for ld in $(losetup -j "$img" 2>/dev/null | cut -d: -f1); do
            losetup -d "$ld" 2>/dev/null
        done
    done
    rm -rf "$DISK_DIR"
    ok "Reset complete."
}

ASSUME_YES=0
DO_RESET=0
for arg in "$@"; do
    case "$arg" in
        --reset) DO_RESET=1 ;;
        --yes|-y) ASSUME_YES=1 ;;
    esac
done
[ "$DO_RESET" = 1 ] && reset_env

#------------------------------------------------------------------------------
# 2. Required packages
#------------------------------------------------------------------------------
info "Installing required packages (needs a working repository)..."
$PKG -y install acl lvm2 e2fsprogs xfsprogs parted tar gzip cronie sudo psmisc \
                util-linux coreutils procps-ng >/dev/null 2>&1 \
    && ok "Packages installed / already present." \
    || warn "Package installation had errors - verify repos if later steps fail."

# Q14 part 1: the candidate must INSTALL 'tree', so make sure it is absent.
$PKG -y remove tree >/dev/null 2>&1
if command -v tree >/dev/null 2>&1; then
    warn "'tree' is still present - Q14 part 1 would auto-pass."
else
    ok "'tree' removed for the Q14 installation task."
fi

# Q14 part 2: the candidate must REMOVE 'zsh', so make sure it is present.
command -v zsh >/dev/null 2>&1 || $PKG -y install zsh >/dev/null 2>&1
if command -v zsh >/dev/null 2>&1; then
    ok "'zsh' installed for the Q14 removal task."
else
    warn "'zsh' could not be installed - Q14 part 2 would auto-pass."
fi

systemctl enable --now crond >/dev/null 2>&1

#------------------------------------------------------------------------------
# 3. SELinux -> permissive (as taught in the course material)
#------------------------------------------------------------------------------
if command -v setenforce >/dev/null 2>&1; then
    setenforce 0 2>/dev/null
    [ -f /etc/selinux/config ] && \
        sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    info "SELinux set to permissive for the exam."
fi

#------------------------------------------------------------------------------
# 4. Exam directories
#------------------------------------------------------------------------------
mkdir -p "$EXPECTED_DIR"
chmod 700 "$EXAM_HOME" "$EXPECTED_DIR"
mkdir -p "$DATA"/{logs,config,data,archive,pub,tmpdir}

#------------------------------------------------------------------------------
# 5. Sample log file  (Q9 - text processing)
#------------------------------------------------------------------------------
cat > "${DATA}/logs/app.log" <<'EOF'
2024-03-01 08:01:12 INFO  10.0.0.11 service started successfully
2024-03-01 08:02:45 WARN  10.0.0.12 disk usage at 78 percent
2024-03-01 08:03:09 ERROR 10.0.0.13 database connection refused
2024-03-01 08:04:31 INFO  192.168.10.4 user alice logged in
2024-03-01 08:05:57 Error 10.0.0.13 retrying database connection
2024-03-01 08:06:22 INFO  172.16.5.20 cache warmed up
2024-03-01 08:07:48 ERROR 192.168.10.4 permission denied on /var/data
2024-03-01 08:08:03 DEBUG 10.0.0.11 heartbeat ok
2024-03-01 08:09:19 error 10.0.0.99 timeout while contacting upstream
2024-03-01 08:10:44 INFO  10.0.0.12 backup job queued
2024-03-01 08:11:02 WARN  172.16.5.20 memory pressure detected
2024-03-01 08:12:37 ERROR 10.0.0.13 database connection refused
2024-03-01 08:13:55 INFO  192.168.10.7 report generated
2024-03-01 08:14:21 ERROR 172.16.5.20 failed to write temporary file
2024-03-01 08:15:40 INFO  10.0.0.11 heartbeat ok
2024-03-01 08:16:12 ERROR 10.0.0.99 upstream returned status 500
2024-03-01 08:17:35 INFO  192.168.10.4 user bob logged in
2024-03-01 08:18:50 WARN  10.0.0.12 disk usage at 81 percent
2024-03-01 08:19:14 Error 192.168.10.7 invalid configuration key
2024-03-01 08:20:39 INFO  172.16.5.20 cache flushed
2024-03-01 08:21:58 ERROR 10.0.0.13 transaction rolled back
2024-03-01 08:22:26 INFO  10.0.0.11 service healthy
2024-03-01 08:23:47 DEBUG 192.168.10.7 gc pause 12ms
2024-03-01 08:24:05 ERROR 10.0.0.99 socket closed unexpectedly
2024-03-01 08:25:29 INFO  10.0.0.12 backup job finished
2024-03-01 08:26:53 WARN  192.168.10.4 slow query detected
2024-03-01 08:27:18 error 172.16.5.20 unable to resolve hostname
2024-03-01 08:28:44 INFO  10.0.0.11 heartbeat ok
2024-03-01 08:29:31 ERROR 192.168.10.7 checksum mismatch on upload
2024-03-01 08:30:59 INFO  10.0.0.12 nightly maintenance scheduled
EOF

#------------------------------------------------------------------------------
# 6. Numbers file (Q9 part c), config files (Q10/Q11)
#------------------------------------------------------------------------------
: > "${DATA}/data/numbers.txt"
for i in $(seq 1 50); do
    printf 'record-%02d value=%d\n' "$i" $((i * 7)) >> "${DATA}/data/numbers.txt"
done

echo "# master configuration file"      >  "${DATA}/config/master.cfg"
echo "listen_port = 8080"               >> "${DATA}/config/master.cfg"
echo "log_level   = info"               >> "${DATA}/config/master.cfg"
echo "app_name = examapp"               >  "${DATA}/config/app.conf"
echo "db_host = 10.0.0.13"              >  "${DATA}/config/db.conf"

#------------------------------------------------------------------------------
# 7. Large files (Q7) with distinct permissions and timestamps
#------------------------------------------------------------------------------
dd if=/dev/zero of="${DATA}/archive/big1.bin" bs=1M count=2 >/dev/null 2>&1
dd if=/dev/zero of="${DATA}/archive/big2.bin" bs=1M count=3 >/dev/null 2>&1
dd if=/dev/zero of="${DATA}/archive/big3.bin" bs=1M count=5 >/dev/null 2>&1
dd if=/dev/zero of="${DATA}/archive/small1.bin" bs=1K count=100 >/dev/null 2>&1
dd if=/dev/zero of="${DATA}/archive/small2.bin" bs=1K count=250 >/dev/null 2>&1

chmod 640 "${DATA}/archive/big1.bin"
chmod 604 "${DATA}/archive/big2.bin"
chmod 755 "${DATA}/archive/big3.bin"
touch -t 202401150900 "${DATA}/archive/big1.bin"
touch -t 202402201430 "${DATA}/archive/big2.bin"
touch -t 202403051115 "${DATA}/archive/big3.bin"

#------------------------------------------------------------------------------
# 8. World-writable files (Q8) and empty files (Q8)
#------------------------------------------------------------------------------
echo "public share notes"  > "${DATA}/pub/open1.txt"
echo "temporary debug log" > "${DATA}/logs/open2.log"
echo "legacy settings"     > "${DATA}/config/open3.cfg"
chmod 777 "${DATA}/pub/open1.txt" "${DATA}/logs/open2.log" "${DATA}/config/open3.cfg"

for f in e1 e2 e3 e4; do : > "${DATA}/tmpdir/${f}.tmp"; done
echo "keep this file"        > "${DATA}/tmpdir/keep1.txt"
echo "keep this one as well" > "${DATA}/tmpdir/keep2.txt"

#------------------------------------------------------------------------------
# 9. Pre-created user for the account-locking task (Q2)
#------------------------------------------------------------------------------
id dev01 >/dev/null 2>&1 || useradd -c "Legacy developer account" dev01
echo "dev01:Str0ngPass#2024" | chpasswd 2>/dev/null
passwd -u dev01 >/dev/null 2>&1

#------------------------------------------------------------------------------
# 10. Rogue service the candidate must stop and disable (Q12)
#------------------------------------------------------------------------------
cat > /usr/local/bin/exam-rogue.sh <<'EOF'
#!/bin/bash
# Simulated runaway workload for the practical exam
while true; do
    sleep 60
done
EOF
chmod 755 /usr/local/bin/exam-rogue.sh

cat > /etc/systemd/system/exam-rogue.service <<'EOF'
[Unit]
Description=Rogue workload (exam scenario)
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/exam-rogue.sh
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now exam-rogue.service >/dev/null 2>&1 \
    && ok "Rogue service exam-rogue.service is running (Q12)." \
    || warn "Could not start exam-rogue.service."

#------------------------------------------------------------------------------
# 11. Two spare disks for the storage / LVM tasks
#     Preference order: (1) devices forced via EXAM_DISK1/EXAM_DISK2,
#                       (2) real unused disks attached in VirtualBox (/dev/sdb...),
#                       (3) loop-backed image files as a fallback.
#------------------------------------------------------------------------------
ROOT_DISK=$(lsblk -nso PKNAME "$(findmnt -no SOURCE / 2>/dev/null)" 2>/dev/null | tail -1)

disk_is_free() {          # $1 = kernel name, e.g. sdb
    local d="$1"
    [ -n "$d" ] || return 1
    [ "$d" = "$ROOT_DISK" ] && return 1
    # any partition, mount, LVM member or filesystem signature disqualifies it
    [ "$(lsblk -nro NAME "/dev/$d" | wc -l)" -eq 1 ] || return 1
    [ -z "$(lsblk -nro MOUNTPOINT "/dev/$d" | tr -d ' ')" ] || return 1
    [ -z "$(lsblk -nro FSTYPE "/dev/$d" | tr -d ' ')" ] || return 1
    return 0
}

detect_real_disks() {     # prints free whole disks of at least 1.5 GB
    local name size
    while read -r name size; do
        [ "$size" -ge 1500000000 ] || continue
        disk_is_free "$name" && echo "/dev/$name"
    done < <(lsblk -dnbro NAME,SIZE,TYPE | awk '$3=="disk"{print $1, $2}')
}

DISK_MODE="real"
if [ -n "$EXAM_DISK1" ] && [ -n "$EXAM_DISK2" ]; then
    DISK1="$EXAM_DISK1"; DISK2="$EXAM_DISK2"
    info "Using disks forced by environment: $DISK1 $DISK2"
else
    mapfile -t FOUND < <(detect_real_disks)
    if [ "${#FOUND[@]}" -ge 2 ]; then
        DISK1="${FOUND[0]}"; DISK2="${FOUND[1]}"
        ok "Detected spare VirtualBox disks: $DISK1 and $DISK2"
    else
        DISK_MODE="loop"
        warn "Fewer than two spare disks found."
        warn "Attach two virtual disks in VirtualBox (Settings > Storage > Add Hard Disk)"
        warn "and re-run this script for a realistic exam. Falling back to loop devices."
    fi
fi

if [ "$DISK_MODE" = "loop" ]; then
    mkdir -p "$DISK_DIR"
    attach_disk() {
        local img="$1" size="$2" ld
        [ -f "$img" ] || truncate -s "$size" "$img"
        ld=$(losetup -j "$img" 2>/dev/null | cut -d: -f1 | head -1)
        [ -z "$ld" ] && ld=$(losetup -P -f --show "$img" 2>/dev/null)
        echo "$ld"
    }
    DISK1=$(attach_disk "${DISK_DIR}/disk1.img" 2G)
    DISK2=$(attach_disk "${DISK_DIR}/disk2.img" 3G)

    # Re-attach the loop disks automatically on boot
    cat > /etc/systemd/system/exam-disks.service <<EOF
[Unit]
Description=Attach practical-exam loop disks
DefaultDependencies=no
Before=local-fs-pre.target lvm2-activation-early.service
Wants=local-fs-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/sbin/losetup -P ${DISK1} ${DISK_DIR}/disk1.img
ExecStart=/sbin/losetup -P ${DISK2} ${DISK_DIR}/disk2.img
ExecStart=/sbin/partprobe ${DISK1}
ExecStart=/sbin/partprobe ${DISK2}
ExecStop=/sbin/losetup -d ${DISK1}
ExecStop=/sbin/losetup -d ${DISK2}

[Install]
WantedBy=sysinit.target
EOF
    systemctl daemon-reload
    systemctl enable exam-disks.service >/dev/null 2>&1
fi

if [ -z "$DISK1" ] || [ -z "$DISK2" ]; then
    fail "Could not provide two exam disks - Q15/Q16 will not be usable."
else
    # Confirm before erasing, unless --yes was given
    if [ "$ASSUME_YES" != "1" ]; then
        echo
        echo "The following devices will be ERASED and handed to the candidate:"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$DISK1" "$DISK2" 2>/dev/null
        printf "Continue? [y/N] "
        read -r reply
        case "$reply" in
            y|Y|yes|YES) ;;
            *) fail "Aborted by operator. No disks were changed."; exit 1 ;;
        esac
    fi

    # Clear any leftover partition table / LVM metadata
    for d in "$DISK1" "$DISK2"; do
        wipefs -a "$d"     >/dev/null 2>&1
        dd if=/dev/zero of="$d" bs=1M count=10 oflag=direct >/dev/null 2>&1 || \
        dd if=/dev/zero of="$d" bs=1M count=10 >/dev/null 2>&1
        partprobe "$d"     >/dev/null 2>&1
    done
    ok "Exam disks ready: DISK1=${DISK1}  DISK2=${DISK2}  (mode: ${DISK_MODE})"
fi

#------------------------------------------------------------------------------
# 12. Pre-compute expected answers used by the grading script
#------------------------------------------------------------------------------
grep -ic error "${DATA}/logs/app.log" > "${EXPECTED_DIR}/errcount.txt"

grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' "${DATA}/logs/app.log" \
    | sort -u > "${EXPECTED_DIR}/ips.txt"

sed -n '10,20p' "${DATA}/data/numbers.txt" > "${EXPECTED_DIR}/lines.txt"

find "$DATA" -type f -size +1M -printf '%f %m %T@\n' 2>/dev/null \
    | sort > "${EXPECTED_DIR}/bigfiles.txt"

find "$DATA" -type f -perm 0777 2>/dev/null | sort > "${EXPECTED_DIR}/ww.txt"

cat > "$ENV_FILE" <<EOF
# Practical exam environment - generated $(date)
EXAM_DISK1="${DISK1}"
EXAM_DISK2="${DISK2}"
EXAM_DISK_MODE="${DISK_MODE}"
EXAM_DATA="${DATA}"
EXAM_EXPECTED="${EXPECTED_DIR}"
EOF
chmod 644 "$ENV_FILE"
chmod 600 "${EXPECTED_DIR}"/*

#------------------------------------------------------------------------------
# 13. Clean any candidate output produced by an earlier attempt
#------------------------------------------------------------------------------
rm -rf /opt/reports /opt/projects /opt/backups
rm -f  /usr/local/bin/examlog.sh /etc/systemd/system/examlog.service \
       /var/log/examlog.log /etc/sudoers.d/sysadmins

#------------------------------------------------------------------------------
# 14. Summary
#------------------------------------------------------------------------------
echo
echo "==============================================================="
echo "            EXAM ENVIRONMENT IS READY"
echo "==============================================================="
printf "  Exam data directory : %s\n" "$DATA"
printf "  Exam disk 1 (Q15)   : %s\n" "$DISK1"
printf "  Exam disk 2 (Q16)   : %s\n" "$DISK2"
printf "  Disk mode           : %s\n" "$DISK_MODE"
printf "  Environment file    : %s\n" "$ENV_FILE"
printf "  Pre-existing user   : dev01\n"
printf "  Rogue service       : exam-rogue.service (active + enabled)\n"
echo "---------------------------------------------------------------"
echo "  Hand the candidate exam_questions.md and start the clock."
echo "  Grade later with:  ./exam_check.sh"
echo "==============================================================="
