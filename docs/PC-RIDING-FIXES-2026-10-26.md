# PC 화면 크래시와 구형 탑승 좌석 데이터

## PC 화면

PC에서 포켓몬 정보창을 연 뒤 닫을 때 More Cobblemon Tweaks 1.3.3이 인자 5개짜리 `PCGUI` 생성자를 호출합니다. Cobblemon 1.8.3에는 마지막 `silent` boolean 인자가 추가된 생성자가 있어 기존 호출은 `NoSuchMethodError`를 발생시킵니다.

공식 More Cobblemon Tweaks **1.3.6-fabric**은 Cobblemon 1.8.2+ 의존성을 명시하며 해당 크래시 수정을 포함합니다. 공식 버전 ID는 `g4m18yE2`입니다. 새 SummaryMixin에서 boolean을 포함한 실제 생성자를 호출하는 것을 확인했습니다.

기존 플레이어는 게임을 종료하고 `mods/MoreCobblemonTweaks-fabric-1.3.3.jar`를 별도 백업 폴더로 옮긴 뒤 공식 `MoreCobblemonTweaks-fabric-1.3.6.jar` 하나를 넣습니다. 전체 모드팩이나 월드를 다시 받을 필요가 없습니다.

공식 파일: https://modrinth.com/mod/more-cobblemon-tweaks/version/g4m18yE2

## 탑승 좌석

데이터팩에는 구형 `offset` / `poseOffsets` 좌석 정의가 있고, 설치된 Cobblemon 1.8.3의 Seat는 `locator`, `condition`, `poseAnimations`, `handsBusy`를 읽습니다. 구형 필드만 있으면 locator는 빈 문자열 기본값으로 남습니다. 이는 모델의 올바른 탑승 위치와 연결되지 않는 데이터 호환성 문제입니다. 특정 사용자가 경험한 카메라 증상의 단독 원인인지 재현 검증한 것은 아닙니다.

활성 모델 리소스의 좌석 locator와 대조해 **231개 포켓몬**의 좌석을 새 형식으로 변환했습니다. 좌석 수가 같고 모델에 모든 위치가 존재하는 경우 공식 좌석 정의를 사용하고, 나머지는 기존 모델의 `seat_1`, `seat_2` 위치를 연결했습니다. 좌석 수·탑승 속도·스태미나·스폰 및 나머지 JSON 데이터는 그대로인 것을 비교 검사했습니다.

다음 예외는 그대로 남깁니다. 없는 모델 위치를 임의로 만들지 않았습니다.

- 펄스멍(Boltund), 드래피온(Drapion): 활성 기본 모델에 확인 가능한 주 좌석 위치가 없음.
- 바리톱스·거북왕·파르셀·삼삼드래: 일부 두 번째 좌석 위치가 없음.
- 메가·지역폼 및 실제 화면의 카메라 회전·떨림은 별도 플레이 확인이 필요함.

데이터팩 변경은 서버에서 다시 로드해야 적용됩니다. 실제 탑승 및 카메라 동작 테스트는 수행하지 않았습니다. Better Third Person이나 카메라 설정을 원인으로 단정해 제거하지 않았습니다.

## 확인 기록

- 공식 모드 다운로드 SHA-512 일치.
- 새 PC 생성자 서명과 설치된 Cobblemon 생성자 서명 일치.
- 데이터팩 ZIP의 변경 항목 231개 확인, 각 항목은 seats 이외 데이터와 좌석 수가 동일.
- 배포 아카이브 CRC 및 모드 해시 검사 통과.
- 게임은 직접 실행하지 않음.

로컬 복구 사본은 Git 제외 `out/integration/more-tweaks-1.3.3-backup/`, `out/integration/riding-seat-backups/`에 보관합니다.
