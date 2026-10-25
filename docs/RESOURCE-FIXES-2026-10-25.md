# 리소스 및 접속 패킷 오류 수정

## 적용한 변경

- Mega Showdown 1.3.2의 `assets/cobblemon/lang/ko_kr.json`: 드래곤옐 설명 뒤에 빠진 쉼표를 추가했습니다. 클라이언트와 새 통합 서버의 같은 JAR에 적용했습니다. 다른 JAR 항목은 변경하지 않았습니다.
- `resourcepackoverrides.json`: 제목·설명 61개의 내부 텍스트 JSON을 올바르게 직렬화했습니다. 외부 JSON 자체는 이미 유효했지만 텍스트 컴포넌트 문자열이 잘못되어 모드가 설정 읽기를 중단했습니다.
- 별도 보정 리소스팩: Cobblenav 화살표의 잘못된 부모 참조 제거, Cobblemon Additions 스포너의 잘못된 네임스페이스 보정, Legendary Monuments 불길한 스포너의 실제 vanilla 모델 참조, Cozyhome 물 텍스처와 Pokeblocks 색이 다른 코고미 인형 텍스처 별칭을 추가했습니다. 내부 falling_liquid 아이템에는 물 양동이 아이콘을 사용합니다.
- 서버에 공식 Fabric 1.21.1 호환 Disconnect Packet Fix 2.0.0을 추가했습니다. SHA-512를 공식 Modrinth 메타데이터와 대조했습니다. 플레이어에게는 필요하지 않습니다.

접속 오류는 [수정 모드의 원본 저장소](https://github.com/ascpixi/disconnect-packet-fix)에 설명된 MC-271325의 메시지 및 스택과 일치합니다. 설치한 수정은 현재 프로토콜에서 지원하지 않는 disconnect 패킷만 차단하는 우회입니다. 실제 연결 실패의 모든 원인을 해결한다는 의미는 아닙니다.

## 검증과 범위

엄격한 한국어 JSON 파싱, 모든 리소스팩 텍스트 컴포넌트 파싱, 보정 모델 부모·텍스처의 실제 파일 존재, JAR의 변경 항목이 한국어 파일 하나뿐인지, 배포 아카이브 CRC와 모드 해시를 확인했습니다.

기존 설치자를 위한 약 9KB의 별도 ZIP도 만들었습니다. Windows PowerShell 패치를 격리된 임시 프로필에서 실행해 한국어 문법 수정, 다른 단축키·그래픽 설정 보존, 백업 생성을 확인했습니다. 테스트에서는 Minecraft 실행 여부 조회만 비어 있는 것으로 모의했으며 실제 사용자 프로필을 테스트 대상으로 사용하지 않았습니다.

수정 후 게임·서버 재실행 검증은 아직 하지 않았습니다. 플레이어의 월드나 진행 데이터는 수정하지 않았고, 운영 서버를 시작하거나 종료하지 않았습니다. 기존 잘못된 로그 및 과거 크래시 보고서는 삭제하지 않았습니다.

퀘스트북의 미등록 `lumymon:zeraorite`, `lumymon:zygardite` 및 NPC 포켓몬 도감 처리의 owner-null 경고는 이번 리소스 수정으로 해결되지 않습니다. 다른 모드의 data fixer 미등록, 버전 표기, 선택적 클래스, 레지스트리 경고도 별개이며 모든 경고가 크래시는 아닙니다.

## 파일

- 수정 소스: `tools/fix-runtime-resources.py`
- 기존 설치자 패치 소스: `resource-fix-patch/`
- 상세 변경: `integration/runtime-resource-fixes.json`
- 정적 검증: `integration/runtime-fix-verification.json`
- 로컬 백업: `out/integration/runtime-fix-backups/` (Git 제외)
- 기존 설치자 ZIP: `out/COBBLEVERSE-Resource-Fixes-2026.10.25.zip` (Git 제외)

제삼자 원본과 수정 바이너리는 Git에 커밋하지 않았으며 공개 Release에도 업로드하지 않았습니다.
