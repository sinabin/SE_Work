# NTP 점검 및 복구 Runbook

## Linux 확인

```bash
ntpq -p
ntpq -c rl
ntpstat
chronyc tracking
chronyc sources -v
systemctl status ntpd chronyd --no-pager
systemctl is-enabled ntpd chronyd
```

## 기본 운영 원칙

- 내부 NTP 기준: `192.168.2.240`
- `NoSync` 제거
- ntpd/chronyd 중 실제 사용하는 데몬 하나만 운영
- 사용 데몬은 부팅 자동시작 상태 확인

## Windows 확인

```cmd
w32tm /query /status
w32tm /query /source
w32tm /query /configuration
```

내부 NTP 지정 예시:

```cmd
w32tm /config /manualpeerlist:"192.168.2.240,0x8" /syncfromflags:manual /reliable:no /update
net stop w32time
net start w32time
w32tm /resync /force
```

> 실제 변경 전 대상 서버가 내부 정책상 해당 NTP를 사용해야 하는지 확인한다.
