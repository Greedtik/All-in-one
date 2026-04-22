# Enterprise Master Operations Tool v4.0

สคริปต์ Bash แบบ All-in-One ที่รวบรวมเครื่องมือสำหรับ System Admin มาไว้ที่เดียว ช่วยลดเวลาและเพิ่มความสะดวกในการเตรียมความพร้อม VM (Provisioning), การติดตั้งระบบ Monitoring, การสแกนช่องโหว่ความปลอดภัย และการตรวจสอบสถานะระบบหลังย้ายเซิร์ฟเวอร์ (Migration) ผ่านเมนูโต้ตอบ (Interactive Menu) ที่ใช้งานง่าย

## 🚀 ความสามารถหลัก (Features)

สคริปต์นี้รวบรวม 4 งานหลักเอาไว้ในเมนูเดียว:

1. **First setup-vm (เตรียมความพร้อม VM ใหม่)**
   - ตรวจสอบระบบปฏิบัติการโดยอัตโนมัติ (รองรับ Debian/Ubuntu/CentOS/RHEL)
   - อัปเดตแพ็กเกจระบบและเคลียร์ไฟล์ขยะ
   - ติดตั้ง Tools พื้นฐานที่จำเป็น (htop, vim, curl, jq, net-tools ฯลฯ)
   - ติดตั้งและเปิดใช้งาน `qemu-guest-agent` สำหรับ Proxmox/OpenStack
   - ตั้งค่า Timezone เป็น `Asia/Bangkok` พร้อมเปิดใช้งานการซิงค์เวลา
   - ปรับแต่งความปลอดภัย SSH เบื้องต้น (มีตัวเลือกให้เปิด/ปิด Password Authentication ได้)

2. **SNMP Install (ติดตั้งและตั้งค่าความปลอดภัย SNMP)**
   - ติดตั้งแพ็กเกจ `snmpd` และ `snmp` แบบอัตโนมัติ
   - มี Prompt ให้ตั้งค่า SNMP Community String เอง (ค่าเริ่มต้นคือ `public`)
   - เสริมความปลอดภัยด้วย View-Based Access Control (VACM) จำกัดสิทธิ์ให้อ่านได้เฉพาะระดับ `systemonly` (.1)
   - มีระบบรันทดสอบตัวเอง (`snmpwalk`) ทันทีหลังติดตั้งเพื่อยืนยันการทำงาน

3. **Soc Scanner (เครื่องมือตรวจจับภัยคุกคามฉบับพกพา)**
   - **Malware & Miner Scan:** สแกนหาโปรแกรมขุดเหรียญที่พบบ่อย (xmrig, kinsing) และไฟล์ซ่อนเร้นใน `/tmp`
   - **Reverse Shell Scan:** ตรวจจับการเชื่อมต่อแบบ Reverse Shell ที่น่าสงสัย
   - **Port Scan:** ตรวจสอบพอร์ตที่มักถูกใช้ในการโจมตี (4444, 31337 ฯลฯ)
   - **User Audit:** ตรวจสอบหาบัญชีแฝงที่มี `UID 0` (สิทธิ์เทียบเท่า root) และบัญชีที่ไม่มีรหัสผ่าน
   - **Persistence Scan:** ตรวจสอบ `cron` ว่ามีการฝังสคริปต์อันตราย (curl, wget) ไว้หรือไม่
   - **Docker Scan:** ตรวจหา Container ที่รันด้วยสิทธิ์ Privileged
   - **CVE Scan:** ตรวจสอบเวอร์ชันแพ็กเกจสำคัญเทียบกับฐานข้อมูลช่องโหว่ผ่าน OSV API

4. **Migration Health Check (ตรวจสอบสุขภาพระบบหลังย้าย Server)**
   - ทำ Health Check ระบบแบบเจาะลึก
   - เช็ก System Load, Uptime, Kernel และการใช้งาน Storage/Inode
   - ตรวจสอบการ Mount ของจุดต่างๆ ในไฟล์ `/etc/fstab` อย่างละเอียด
   - ทดสอบเครือข่าย (Default Gateway, Internet, DNS)
   - เช็กสถานะ Service หลัก (sshd, nginx, apache2, mysql ฯลฯ)
   - สแกนหา Enterprise Suites (Zimbra, cPanel) และแอปพลิเคชันที่ติดตั้งเพิ่มเติมใน `/opt`
   - สร้างสรุปผล (Executive Summary) และบันทึก Log เก็บไว้ตรวจสอบย้อนหลัง

## ⚙️ ระบบที่รองรับ (Requirements)

- **OS:** Debian, Ubuntu, CentOS, RHEL, Rocky Linux, หรือ AlmaLinux
- **สิทธิ์ผู้ใช้งาน:** จำเป็นต้องรันด้วยสิทธิ์ `root` เท่านั้น

## 🛠️ วิธีการใช้งาน (Usage)

สามารถเรียกรันสคริปต์นี้จาก Git ได้โดยตรง โดยไม่ต้องโคลน (Clone) Repository ลงมาให้รกเครื่อง 

**วิธีที่ 1: รันผ่าน Process Substitution (แนะนำที่สุด สำหรับใช้งานเมนู)**
*เข้าใช้งานด้วยสิทธิ์ root (`sudo su -`) ก่อนรันคำสั่งนี้:*
```bash
bash <(curl -sL https://raw.githubusercontent.com/Greedtik/All-in-one/refs/heads/main/all-in-one.sh)
```
# 📝 การเก็บบันทึกข้อมูล (Logging)
สคริปต์แต่ละเมนูจะมีการแยกเก็บไฟล์ Log ไว้ เพื่อความสะดวกในการตรวจสอบย้อนหลัง:

VM Provisioning: /var/log/vm-provisioning.log

Health Check: /var/log/migration_audit_<date>.log
