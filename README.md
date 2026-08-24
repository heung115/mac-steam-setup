# Mac Steam Setup

[한국어](README.md) | [English](README_EN.md)

<p align="center">
  <img src="Assets/AppIcon.png" width="128" alt="Mac Steam Setup 아이콘">
</p>

**Apple Silicon Mac에서 Windows Steam과 Windows 전용 게임을 더 쉽게 설치하고 실행하는 도구입니다.** Sikarugir/Wine 방식을 간단한 Mac 앱으로 준비합니다.

[베타 다운로드](https://github.com/heung115/mac-steam-setup/releases) · [의견 나누기](https://github.com/heung115/mac-steam-setup/discussions) · [버그·게임 호환성 제보](https://github.com/heung115/mac-steam-setup/issues/new/choose)

[![CI](https://github.com/heung115/mac-steam-setup/actions/workflows/ci.yml/badge.svg)](https://github.com/heung115/mac-steam-setup/actions/workflows/ci.yml) ![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black) ![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-black) [![MIT License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

이 프로젝트는 비상업적 오픈소스 프로토타입입니다. 자체 Wine이나 Steam을 포함하지 않고, 고정된 공식 Sikarugir 엔진/템플릿과 Valve의 Steam 설치 파일을 실행 시점에 내려받습니다.

이 프로젝트는 독립적인 비공식 커뮤니티 프로젝트이며 Valve Corporation, Apple Inc. 또는 Sikarugir 프로젝트와 제휴하거나 이들로부터 승인·후원받지 않았습니다. Steam 및 Steam 로고는 Valve Corporation의 상표 또는 등록상표입니다. 이 프로젝트는 Steam 로고나 Valve의 공식 디자인 자산을 사용하지 않습니다.

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

### 베타 앱 다운로드

1. [GitHub Releases](https://github.com/heung115/mac-steam-setup/releases)에서 최신 `Mac-Steam-Setup-*.dmg`를 받습니다.
2. DMG를 열고 `Mac Steam Setup.app`을 함께 보이는 `Applications` 폴더로 드래그합니다.
3. 첫 실행은 앱을 우클릭(또는 Control-클릭)하고 `열기`를 선택합니다.
4. macOS가 계속 차단하면 앱을 한 번 실행해 본 뒤 `시스템 설정 → 개인정보 보호 및 보안 → 그래도 열기`를 선택합니다. 한 번 승인하면 이후에는 평소처럼 더블클릭할 수 있습니다.

현재 베타는 Apple의 서명·공증을 받지 않았습니다. GitHub 저장소에서 직접 받은 파일인지 확인하고, 함께 제공되는 `.sha256` 체크섬으로 다운로드가 손상되지 않았는지 확인할 수 있습니다. DMG가 열리지 않는 경우에는 같은 Release의 ZIP을 대신 사용할 수 있습니다.

### 소스에서 빌드

```sh
./build.command
```

생성된 `build/Mac Steam Setup.app`을 열고 `Windows Steam 준비하기`를 누릅니다. Steam 설치창에서는 기본 경로로 설치 완료까지 진행하면 됩니다. 마지막의 Steam 실행 여부와 관계없이 설치 도우미가 첫 실행을 정리하고 최종 설정으로 넘어갑니다.

Steam은 네트워크 환경에 따라 초기 연결 검사에 약 1분이 걸릴 수 있습니다. 정상적인 빠른 실행에서도 IPv6 검사 `TIMEOUT`이 기록될 수 있으므로 이 문구만으로 오류를 판단하지 않습니다. 재현 조건과 후속 조사 절차는 [Windows Steam 시작 지연 조사 기록](docs/diagnostics/steam-startup-network-delay.md)에 정리했습니다. Wine 초기 updater가 한국어 글꼴을 표시하지 못하므로 Steam 언어는 영어 기본값으로 준비합니다. Steam 설정에서 한국어로 바꿀 수 있지만 이후 updater의 한글이 네모로 보일 수 있습니다.

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

## 의견과 게임 호환성 제보

사용해 본 결과가 프로젝트 개선에 가장 큰 도움이 됩니다.

- 사용 후기, 질문, 아이디어: [GitHub Discussions](https://github.com/heung115/mac-steam-setup/discussions)
- 설치·실행 오류: [버그 신고 양식](https://github.com/heung115/mac-steam-setup/issues/new?template=bug-report.yml)
- 실행해 본 Windows 게임: [게임 호환성 제보 양식](https://github.com/heung115/mac-steam-setup/issues/new?template=game-compatibility.yml)

잘 실행된 게임도 알려주세요. 제보할 때 계정 이름, 이메일, 로컬 파일 경로 등 개인정보가 로그나 화면에 포함되지 않았는지 확인해 주세요.

## 바이너리 배포

CI에서 빌드한 작은 설치 앱은 Steam, Wine, D3DMetal 또는 Sikarugir 엔진/템플릿을 포함하지 않는 조건으로 배포할 수 있습니다. 제3자 구성요소는 반드시 현재처럼 사용자의 Mac에서 공식 배포 주소로 직접 내려받아야 합니다.

`build.command`가 만드는 앱은 로컬 테스트용 임시(ad-hoc) 서명입니다. 다른 사용자에게 GitHub Release 등으로 배포하려면 Apple Developer Program의 Developer ID로 서명하고 Apple 공증을 받은 뒤 ZIP 또는 DMG로 제공하는 것을 권장합니다. 서명 인증서와 공증 자격 증명은 저장소에 올리지 말고 CI의 암호화된 비밀값으로 관리해야 합니다.

## 라이선스 경계

이 저장소의 자체 코드는 MIT입니다. MIT 허가는 Sikarugir, Wine, D3DMetal, Steam 또는 게임에 대한 권리를 부여하지 않습니다. 완성된 `Steam.app`, Steam 클라이언트, 게임, Sikarugir 엔진/템플릿은 릴리스에 포함하면 안 됩니다. 자세한 내용은 `THIRD_PARTY_NOTICES.md`를 확인하세요.
