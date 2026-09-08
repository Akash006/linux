# Linux Practical Examination — Instructor Answer Key

**Platform:** CentOS Stream 10 · **Total:** 100 marks · **Pass:** 80

> For instructor use only. Every command below is what `exam_check.sh` expects to see the
> *effect* of — alternative commands that produce the same end state also score full marks.
> Run all of these as `root`.

---

## Question 1 — Users and groups (7)

```bash
groupadd -g 5000 sysadmins
useradd -G sysadmins -s /bin/bash alice
useradd -G sysadmins -s /bin/bash bob
useradd -u 3005 -s /sbin/nologin -c "Service Account" carol
```

**Verify**

```bash
getent group sysadmins        # sysadmins:x:5000:alice,bob
id alice; id bob; id carol
getent passwd carol
```

**Marks:** GID 5000 (2) · alice+bob with `/bin/bash` (2) · both in `sysadmins` (1) · carol UID 3005 + nologin (1) · comment field `Service Account` (1)

**Common errors:** using `-g sysadmins` (makes it the *primary* group, wiping the private group) instead of `-G`; forgetting to quote `"Service Account"`.

---

## Question 2 — Password ageing and account locking (5)

```bash
chage -M 45 -m 3 -W 7 alice
usermod -L dev01          # or: passwd -l dev01
```

**Verify**

```bash
chage -l alice
passwd -S dev01           # dev01 LK ...
```

**Marks:** max 45 (2) · min 3 (1) · warn 7 (1) · dev01 locked (1)

**Common errors:** `usermod -e` (account expiry) confused with `-M` (password max age); deleting `dev01` instead of locking it.

---

## Question 3 — Superuser access (5)

```bash
echo '%sysadmins ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/sysadmins
chmod 0440 /etc/sudoers.d/sysadmins
visudo -c
```

(`visudo -f /etc/sudoers.d/sysadmins` is the safer, equally acceptable route.)

**Verify**

```bash
sudo -l -U alice          # must show (ALL) NOPASSWD: ALL
```

**Marks:** file exists (1) · `visudo -c` clean (1) · alice NOPASSWD ALL (2) · bob NOPASSWD ALL (1)

**Common errors:** writing `sysadmins` without the leading `%`; a typo that breaks `visudo -c` and therefore invalidates *all* sudo rules.

---

## Question 4 — Ownership and permissions (5)

```bash
mkdir -p /opt/projects/webapp
chown alice:sysadmins /opt/projects/webapp
chmod 770 /opt/projects/webapp

touch /opt/projects/webapp/notes.txt
chown bob:sysadmins /opt/projects/webapp/notes.txt
chmod 640 /opt/projects/webapp/notes.txt
```

**Verify:** `ls -ld /opt/projects/webapp; ls -l /opt/projects/webapp/notes.txt`

**Marks:** directory exists (1) · `alice:sysadmins` (2) · mode 770 (1) · notes.txt `bob:sysadmins` 640 (1)

---

## Question 5 — Access Control Lists (6)

```bash
setfacl -m u:bob:rwx /opt/projects/webapp
setfacl -d -m u:carol:rx /opt/projects/webapp
```

**Verify**

```bash
getfacl /opt/projects/webapp
# user:bob:rwx
# default:user:carol:r-x
```

**Marks:** `user:bob:rwx` (3) · `default:user:carol:r-x` (3)

**Common errors:** omitting `-d`, so the carol entry lands on the directory instead of being inherited; using `setfacl -m d:u:carol:rx` is fine (same result).

---

## Question 6 — umask (4)

```bash
echo 'umask 0027' >> /home/alice/.bash_profile
chown alice:alice /home/alice/.bash_profile
```

**Verify:** `su - alice -c umask`  → `0027`

**Marks:** effective umask 0027 (2) · persistent in a login file (2)

**Common errors:** editing `/etc/profile` (changes it for everyone — the question forbids that); putting it in `/root/.bashrc`.

---

## Question 7 — Locating and copying large files (5)

```bash
mkdir -p /opt/reports/bigfiles
find /exam-data -type f -size +1M -exec cp -p {} /opt/reports/bigfiles/ \;
```

Expected files: `big1.bin` (2 M, 640), `big2.bin` (3 M, 604), `big3.bin` (5 M, 755).

**Verify:** `ls -l /opt/reports/bigfiles/`

**Marks:** directory (1) · all three copied (2) · permissions preserved (1) · timestamps preserved (1)

**Common errors:** plain `cp` without `-p` loses both mode and mtime — costs 2 marks; `-size +1000k` also works.

---

## Question 8 — Permission audit and cleanup (5)

```bash
find /exam-data -type f -perm 0777 | sort > /opt/reports/world-writable.txt
find /exam-data/tmpdir -type f -empty -delete
```

Expected list: `/exam-data/config/open3.cfg`, `/exam-data/logs/open2.log`, `/exam-data/pub/open1.txt`

**Marks:** exact sorted list (3) · empty files gone (1) · `keep1.txt`/`keep2.txt` intact (1)

**Common errors:** `-perm 777` vs `-perm -777` (the latter matches "at least these bits"); `rm -f /exam-data/tmpdir/*` deletes the keep files too.

---

## Question 9 — Log analysis (9)

```bash
# a) count of lines containing "error", any case
grep -ic error /exam-data/logs/app.log > /opt/reports/error-count.txt      # 12

# b) unique sorted IPv4 addresses
grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' /exam-data/logs/app.log \
    | sort -u > /opt/reports/ips.txt                                       # 7 addresses

# c) lines 10-20 of numbers.txt
head -20 /exam-data/data/numbers.txt | tail -11 > /opt/reports/lines10-20.txt
# equivalent: sed -n '10,20p' /exam-data/data/numbers.txt
```

Expected IPs: `10.0.0.11`, `10.0.0.12`, `10.0.0.13`, `10.0.0.99`, `172.16.5.20`, `192.168.10.4`, `192.168.10.7`

**Marks:** 3 per part. Comparison ignores trailing whitespace and blank lines.

**Common errors:** `grep -c` without `-i` returns 8, not 12; `sort | uniq` without `-u`/`uniq` leaves duplicates; off-by-one on part (c) — it is 11 lines, not 10.

---

## Question 10 — Hard and soft links (4)

```bash
ln    /exam-data/config/master.cfg /opt/reports/master.hard
ln -s /exam-data/config/master.cfg /opt/reports/master.soft
```

**Verify:** `ls -li /exam-data/config/master.cfg /opt/reports/master.*` — the hard link shares the inode and shows link count 2.

**Marks:** hard link, same inode, not a symlink (2) · symlink resolving to master.cfg (2)

**Common errors:** creating the symlink with a *relative* target from the wrong directory, leaving it dangling.

---

## Question 11 — Archiving (4)

```bash
mkdir -p /opt/backups
tar -czvf /opt/backups/exam-data.tar.gz -C /exam-data config
# also accepted: tar -czvf /opt/backups/exam-data.tar.gz /exam-data/config
```

**Verify:** `tar -tzf /opt/backups/exam-data.tar.gz`

**Marks:** gzip archive exists (1) · contains `config/master.cfg` (2) · contains `app.conf` and `db.conf` (1)

**Common errors:** forgetting `-z` (plain tar named `.tar.gz`); archiving only the single file.

---

## Question 12 — Terminate the rogue workload (5)

```bash
systemctl stop exam-rogue.service
systemctl disable exam-rogue.service
pkill -f exam-rogue.sh        # only if anything survived
```

**Verify:** `systemctl status exam-rogue.service; pgrep -af exam-rogue.sh`

**Marks:** not active (2) · not enabled (2) · no matching process (1)

**Common errors:** only `kill`ing the PID — `Restart=always` respawns it immediately, so the service must be stopped; only stopping it, which loses the "not enabled" marks. `systemctl mask` also satisfies the enable check.

---

## Question 13 — Custom systemd service (8)

```bash
cat > /usr/local/bin/examlog.sh <<'EOF'
#!/bin/bash
while true; do
    echo "I'm running @ $(date)" >> /var/log/examlog.log
    sleep 10
done
EOF
chmod +x /usr/local/bin/examlog.sh

cat > /etc/systemd/system/examlog.service <<'EOF'
[Unit]
Description=Exam logging service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/examlog.sh

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now examlog.service
```

**Verify**

```bash
systemctl status examlog.service
tail -f /var/log/examlog.log
```

**Marks:** script exists + executable (2) · unit file present (1) · active (2) · enabled (2) · log actively growing — the grader waits 25 s (1)

**Common errors:** missing shebang or missing `chmod +x` → `status=203/EXEC`; forgetting `daemon-reload`; forgetting `[Install]`, which makes `enable` fail; `Type=forking` on a foreground script.

---

## Question 14 — Package management (4)

```bash
dnf install -y tree
dnf remove  -y zsh
```

**Verify**

```bash
dnf list --installed tree
dnf list --installed zsh      # must return nothing
```

**Marks:** tree installed (2) · zsh removed (2)

**Note:** CentOS Stream 10 ships DNF 4 with `yum` as a compatibility symlink, so `yum install tree` is equally acceptable.

---

## Question 15 — Partition, file system, persistent mount (8)

Assume `$EXAM_DISK1` is `/dev/sdb`.

```bash
source /etc/exam/exam.env

fdisk $EXAM_DISK1
#  n → p → 1 → <Enter> → +500M → w
# equivalent: parted -s $EXAM_DISK1 mklabel msdos mkpart primary ext4 1MiB 501MiB

partprobe $EXAM_DISK1
mkfs.ext4 -L EXAMDATA ${EXAM_DISK1}1

mkdir -p /mnt/examdata
blkid ${EXAM_DISK1}1                     # note the UUID
echo 'UUID=<uuid-here> /mnt/examdata ext4 defaults 0 0' >> /etc/fstab
# equally valid: LABEL=EXAMDATA /mnt/examdata ext4 defaults 0 0

systemctl daemon-reload
mount -a
```

**Verify:** `findmnt /mnt/examdata; df -h /mnt/examdata; lsblk -f`

**Marks:** mounted (2) · ext4 (2) · label EXAMDATA (1) · ~500 MiB, 400–560 accepted (1) · fstab entry (2)

**Common errors:** forgetting `partprobe`, so the kernel never sees the partition; labelling with `e2label` is fine but must actually be run; mounting by device name is accepted by the grader, but UUID/LABEL is the professional answer.

---

## Question 16 — LVM (10)

Assume `$EXAM_DISK2` is `/dev/sdc`.

```bash
source /etc/exam/exam.env

pvcreate $EXAM_DISK2                     # whole-disk PV is fine
vgcreate vgexam $EXAM_DISK2
lvcreate -L 512M -n lvdata vgexam
mkfs.xfs /dev/vgexam/lvdata

mkdir -p /mnt/lvdata
echo '/dev/vgexam/lvdata /mnt/lvdata xfs defaults 0 0' >> /etc/fstab
systemctl daemon-reload
mount -a

# --- the extend, online ---
lvextend -L 1G -r /dev/vgexam/lvdata
# without -r:  lvextend -L 1G /dev/vgexam/lvdata && xfs_growfs /mnt/lvdata
```

Creating a partition of type `8e` first, then `pvcreate ${EXAM_DISK2}1`, is equally correct.

**Verify:** `vgs; lvs; df -h /mnt/lvdata` → about 1 G available

**Marks:** VG vgexam (2) · LV lvdata (1) · LV ≈ 1 GiB (2) · mounted with xfs (2) · file system grown (2) · fstab entry (1)

**Common errors:** extending the LV but forgetting to grow the file system — `df` still shows 512 M, costing 2 marks; using `resize2fs` on xfs (wrong tool); `-L 1G` vs `-L +1G` (the latter gives 1.5 G and falls outside the accepted range). Note that on RHEL/CentOS 10 `mkfs.xfs` refuses file systems below 300 MB, which is why the starting LV is 512 MiB.

---

## Question 17 — Scheduled job (3)

```bash
crontab -u alice -e
```

Entry:

```
*/5 * * * * date >> /home/alice/cron-report.txt
```

**Verify:** `crontab -l -u alice`

**Marks:** `*/5 * * * *` schedule (2) · appends to `/home/alice/cron-report.txt` (1)

**Common errors:** creating it under root's crontab; using `5 * * * *` (once an hour at minute 5); using `>` instead of `>>`.

---

## Question 18 — Hostname (3)

```bash
hostnamectl set-hostname exam-node1.example.com
# equivalent: nmcli general hostname exam-node1.example.com
echo exam-node1.example.com > /opt/reports/hostname.txt
```

**Verify:** `hostnamectl --static; cat /etc/hostname`

**Marks:** static hostname set (2) · file contains it (1)

**Common errors:** `hostname exam-node1.example.com` alone — runtime only, lost on reboot.

---

## Marking summary

| Q | Topic | Marks | Q | Topic | Marks |
|---|---|---|---|---|---|
| 1 | Users and groups | 7 | 10 | Hard and soft links | 4 |
| 2 | Password ageing / locking | 5 | 11 | tar archive | 4 |
| 3 | sudo | 5 | 12 | Stop rogue service | 5 |
| 4 | Ownership and permissions | 5 | 13 | Custom systemd service | 8 |
| 5 | ACLs | 6 | 14 | dnf install / remove | 4 |
| 6 | umask | 4 | 15 | Partition + fstab | 8 |
| 7 | find + `cp -p` | 5 | 16 | LVM create and extend | 10 |
| 8 | Permission audit | 5 | 17 | cron | 3 |
| 9 | Log analysis | 9 | 18 | Hostname | 3 |

**Total 100 · Pass mark 80**

---

## Grading notes for the invigilator

- Run `./exam_check.sh <candidate-name>` as root on the candidate's VM. It takes about 30 seconds (it waits 25 s to confirm the Q13 log file is growing) and writes a transcript to `/root/exam-result-<name>-<date>.txt`.
- The grader scores the **end state**, not the commands used, so any correct method earns the marks.
- Answer keys for Q9 and Q8 live in `/etc/exam/expected/` (mode 600) and were generated when `exam_setup.sh` ran, so editing `/exam-data` afterwards cannot make a wrong answer pass.
- A reboot before grading is a fair sanity test of the "must survive a reboot" rule — Q13, Q15, Q16, Q17 and Q18 are the ones it catches.
- To reuse the VM for the next candidate: `./exam_setup.sh --reset --yes`.
