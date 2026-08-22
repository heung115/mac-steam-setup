# Mac Steam Setup

Apple Silicon Mac에서 Windows Steam 환경을 Sikarugir 방식으로 준비하는 비상업적 프로토타입입니다. 자체 Wine이나 Steam을 포함하지 않고, 고정된 공식 Sikarugir 엔진/템플릿과 Valve의 Steam 설치 파일을 실행 시점에 내려받습니다.

## 현재 기능

- 단계별 전체 진행률과 다운로드 용량 표시
- 중복 설치 및 중복 실행 차단
- Steam 설치창 종료 후 남는 Sikarugir 대기 프로세스 자동 정리
- D3DMetal 및 Steam 실행 경로 자동 설정
- 백그라운드 Sikarugir Dock 아이콘 숨김
- Steam 로그인 웹 캐시 복구
- Windows Steam과 실행 중인 Windows 게임 완전 종료
- 설치된 게임을 읽어 가벼운 Mac 앱 바로가기 생성
- 기존 macOS Steam과 Porting Kit는 변경하지 않음

## 사용

```sh
./build.command
```

생성된 `build/Mac Steam Setup.app`을 열고 `Windows Steam 준비하기`를 누릅니다. Steam 설치창에서는 기본 경로로 설치 완료까지 진행하면 됩니다. 마지막의 Steam 실행 여부와 관계없이 설치 도우미가 첫 실행을 정리하고 최종 설정으로 넘어갑니다.

Steam은 업데이트 확인에 약 1분이 걸릴 수 있습니다. Wine 초기 updater가 한국어 글꼴을 표시하지 못하므로 Steam 언어는 영어 기본값으로 준비합니다. Steam 설정에서 한국어로 바꿀 수 있지만 이후 updater의 한글이 네모로 보일 수 있습니다.

게임 설치 후 `게임 바로가기`에서 Mac 앱을 만들 수 있습니다. 바로가기는 Wine 환경이나 게임 파일을 복제하지 않으며, Steam을 백그라운드로 시작한 다음 해당 App ID를 실행합니다. Steam DRM을 사용하는 게임은 Steam 프로세스 자체를 생략할 수 없습니다.

## 검증

```sh
bash Tests/run.sh
```

테스트는 설치 상태 판정, 단조 증가 진행률, Steam 설치 완료 결정, 래퍼 설정, 중복 실행 식별, 캐시 복구, 완전 종료 프로토콜, 게임 manifest 파싱과 바로가기 생성/서명을 검사합니다.

실기기에서는 macOS 26.6.2 / M4 Pro와 Steam 빌드 `1785799196`에서 다음을 확인했습니다.

- Steam 설치 및 최신 클라이언트 업데이트
- 로그인 창 렌더링과 `steamwebhelper` 5분 이상 유지
- 로그인 캐시 초기화 후 재실행
- 중복 실행 요청 차단
- Sikarugir 실행기 Dock 아이콘 숨김
- Windows Steam 전체 프로세스 종료 후 재실행

게임별 실행 성공 여부와 안티치트 호환성은 게임마다 다릅니다.

## 라이선스 경계

이 저장소의 자체 코드는 MIT입니다. MIT 허가는 Sikarugir, Wine, D3DMetal, Steam 또는 게임에 대한 권리를 부여하지 않습니다. 완성된 `Steam.app`, Steam 클라이언트, 게임, Sikarugir 엔진/템플릿은 릴리스에 포함하면 안 됩니다. 자세한 내용은 `THIRD_PARTY_NOTICES.md`를 확인하세요.
