# Mac Steam Setup — PROTOTYPE

검증 질문:

> 유튜브의 Sikarugir 설치 방식을 비전문 사용자가 터미널 없이 한 버튼으로 완료할 수 있는가?

이 프로토타입은 자체 Wine을 만들지 않습니다. 고정된 공식 Sikarugir 엔진/템플릿과 공식 Windows Steam 설치 파일을 실행 시점에 내려받아 `~/Applications/Sikarugir/Steam.app`을 만듭니다. Homebrew나 Sikarugir Creator는 설치하지 않으며, Rosetta 2가 없으면 Apple 공식 설치 기능으로 자동 준비합니다.

빌드:

```sh
./build.command
```

생성물은 `build/Mac Steam Setup.app`입니다. 설치 백엔드는 기존 래퍼를 삭제하거나 덮어쓰지 않습니다.

## 현재 검증 결과

- macOS 26.6.2 / M4 Pro에서 버튼 한 번으로 고정 엔진, 래퍼, Windows Steam 설치와 D3DMetal 설정까지 완료했습니다.
- 생성된 설치 앱은 약 348KB, Windows Steam 래퍼는 업데이트 후 약 3.1GB입니다.
- 2026-08-22 Steam 빌드 `1785799196`에서 첫 로그인 창이 `Loading user data...`에 멈추는 증상을 재현했습니다.
- 동일 엔진과 D3DMetal 설정을 유지한 채 Wine 사용자 폴더의 Steam `htmlcache`만 초기화하자 로그인 입력창과 QR 코드가 정상 표시됐습니다. 설치 앱의 `로그인 화면 복구` 버튼으로 같은 조치를 다시 할 수 있습니다.

백엔드는 CC0 저장소 `mirpo/windows-steam-on-apple-silicon`의 커밋 `0c8717408d85fe5a2a901b84db6a984617c4ce2a`를 참고했습니다. 엔진과 템플릿은 앱에 포함하지 않고 공식 고정 URL에서 내려받으며 SHA-256을 확인합니다.
