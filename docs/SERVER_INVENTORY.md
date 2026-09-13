# Server Inventory / Known Roles

> 이 문서는 프로젝트에서 확인된 운영 맥락을 요약한 것이다. 실제 역할/버전/상태는 변경될 수 있으므로 작업 전 서버에서 재확인한다.

| 서버/그룹 | 확인된 역할 또는 특징 |
|---|---|
| xcat | 중앙 운영, pdsh, Linux dailycheck/sysmon, Ansible, MySQL 모니터링 데이터 |
| ccnweb1/2 | Apache httpd 계열 Web, NFS 관련 점검 |
| ccnwas1/2 | Tomcat 다중 인스턴스, Apache, NFS, OZ Report 관련 운영 |
| ccndb | Oracle 계열 DB, NFS 공유 `/share`, `/sharebackup` 등 |
| ccnsearch | Solaris, 일반 Linux와 다른 수집 경로, 검색 계열 프로세스 |
| ccnengine | WiseNut 검색/FTP 계열 운영 이력 |
| ccnjennifer | Jennifer APM |
| ccnmail | 메일 시스템, Tomcat 계열 운영 이력 |
| ccnmessanger | 메신저/Tomcat 계열 |
| ccnprivacy / HyBoostH100 | 개인정보/Privacy-i 계열, 과거 NTP 특수 조치 이력 |
| hyboost_visual | Tomcat 9 계열 운영 이력 |
| ccnrecdba / ccnrecdbb | 녹취/DB 계열, MySQL/NFS/Samba 관련 프로세스 |
| ccnmirror01/02 | 미러/스토리지 계열, Samba/SSH 관련 프로세스 |
| ccnbib01/02 | 녹취/음성 계열, Tomcat 및 `/media` 용량 주의 이력 |
| ccnstaters01 | Oracle/Java/Tomcat 계열, `/app`, `/data`, `/home` 주요 마운트 |
| dbsafer | DB 보안 솔루션 계열 |
| spam | 스팸/보안 솔루션, Apache 계열 프로세스 |
| sms_server | SMS 계열 Java 프로세스, NFS |
| ccnvmstorage01 | FTP/NFS 계열 |
| ccnrecstorage01 | NFS 스토리지 계열 |
| ccnsbc1/2 | SBC/네트워크 애플리케이션 계열 |
| elearning | Java/연계 배치 계열 |
| apiproxy | Squid 프록시 계열 |

## Windows

상세 Xcat Ansible 문서 기준으로 과거 `win_dailycheck` 대상 16대가 확인되어 있다.
실제 현재 인벤토리는 `/etc/ansible/hosts` Vault 내용을 기준으로 재확인한다.

## 서버별 감시 프로세스

현재 프로젝트의 `config/server_service_list.txt`를 우선 참고한다.
이는 실제 `monitor_dashboard.sh`의 서비스 매핑 입력 파일로 사용되는 구조다.

## 계정 점검 대상

`config/server_account_list.txt`에 호스트별 계정 점검 대상이 정리되어 있다.
계정 자체는 운영정보이므로 외부 공개 문서에는 그대로 노출하지 않는 것을 권장한다.
