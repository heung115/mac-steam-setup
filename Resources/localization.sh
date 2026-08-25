#!/bin/bash

macsteam_ui_language() {
  case "${MACSTEAM_UI_LANGUAGE:-}" in
    ko|en) printf '%s\n' "$MACSTEAM_UI_LANGUAGE"; return ;;
  esac

  local languages first_language
  languages="$(/usr/bin/defaults read -g AppleLanguages 2>/dev/null || true)"
  first_language="$(printf '%s\n' "$languages" | /usr/bin/awk -F '"' 'NF >= 3 { print $2; exit }')"
  if [[ "$first_language" == ko* ]]; then
    printf 'ko\n'
  else
    printf 'en\n'
  fi
}

MACSTEAM_RESOLVED_LANGUAGE="$(macsteam_ui_language)"

ui_text() {
  local key="$1"
  shift
  local format

  case "$MACSTEAM_RESOLVED_LANGUAGE:$key" in
    ko:steam_language_environment_missing) format='Steam 언어 설정에 필요한 Wine 환경을 찾을 수 없습니다' ;;
    en:steam_language_environment_missing) format='The Wine environment required to configure the Steam language was not found' ;;
    ko:steam_language_config_failed) format='Steam 초기 언어를 설정하지 못했습니다' ;;
    en:steam_language_config_failed) format='Could not configure the initial Steam language' ;;
    ko:unsafe_lock_path) format='설치 잠금 위치가 안전하지 않습니다' ;;
    en:unsafe_lock_path) format='The setup lock path is unsafe' ;;
    ko:installation_already_running) format='이미 설치가 진행 중입니다' ;;
    en:installation_already_running) format='Setup is already running' ;;
    ko:stale_lock_cleanup_failed) format='이전 설치 잠금을 정리하지 못했습니다' ;;
    en:stale_lock_cleanup_failed) format='Could not remove the stale setup lock' ;;
    ko:installed_steam_not_found) format='설치된 Windows Steam을 찾을 수 없습니다' ;;
    en:installed_steam_not_found) format='The installed Windows Steam app was not found' ;;
    ko:steam_window_reopen_failed) format='Steam 창을 다시 열지 못했습니다' ;;
    en:steam_window_reopen_failed) format='Could not reopen the Steam window' ;;
    ko:steam_window_foregrounded) format='Windows Steam 창을 앞으로 가져왔습니다' ;;
    en:steam_window_foregrounded) format='Brought the Windows Steam window to the front' ;;
    ko:steam_stalled_restarting) format='멈춘 Steam 시작을 정리하고 다시 여는 중입니다' ;;
    en:steam_stalled_restarting) format='Cleaning up a stalled Steam launch and trying again' ;;
    ko:steam_stalled_cleanup_failed) format='멈춘 Windows Steam을 정리하지 못했습니다' ;;
    en:steam_stalled_cleanup_failed) format='Could not clean up the stalled Windows Steam launch' ;;
    ko:steam_starting) format='Windows Steam을 시작하고 있습니다' ;;
    en:steam_starting) format='Starting Windows Steam' ;;
    ko:steam_start_requested) format='Windows Steam 시작을 요청했습니다' ;;
    en:steam_start_requested) format='Requested Windows Steam to start' ;;
    ko:steam_stopping) format='Windows Steam과 실행 중인 Windows 게임을 종료하고 있습니다' ;;
    en:steam_stopping) format='Stopping Windows Steam and running Windows games' ;;
    ko:steam_launcher_not_found) format='Windows Steam 실행기를 찾을 수 없습니다' ;;
    en:steam_launcher_not_found) format='The Windows Steam launcher was not found' ;;
    ko:steam_stop_failed) format='Windows Steam을 완전히 종료하지 못했습니다' ;;
    en:steam_stop_failed) format='Could not completely stop Windows Steam' ;;
    ko:steam_stopped) format='Windows Steam을 완전히 종료했습니다' ;;
    en:steam_stopped) format='Windows Steam was completely stopped' ;;
    ko:no_installed_games) format='설치된 Windows Steam 게임이 없습니다' ;;
    en:no_installed_games) format='No installed Windows Steam games were found' ;;
    ko:invalid_game_id) format='올바른 Steam 게임 ID가 아닙니다' ;;
    en:invalid_game_id) format='The Steam game ID is invalid' ;;
    ko:game_info_not_found) format='설치된 게임 정보를 찾을 수 없습니다' ;;
    en:game_info_not_found) format='The installed game information was not found' ;;
    ko:game_info_read_failed) format='게임 정보를 읽지 못했습니다' ;;
    en:game_info_read_failed) format='Could not read the game information' ;;
    ko:game_id_mismatch) format='게임 ID가 설치 정보와 일치하지 않습니다' ;;
    en:game_id_mismatch) format='The game ID does not match the installed game information' ;;
    ko:game_name_read_failed) format='게임 이름을 읽지 못했습니다' ;;
    en:game_name_read_failed) format='Could not read the game name' ;;
    ko:game_install_read_failed) format='게임 설치 정보를 읽지 못했습니다' ;;
    en:game_install_read_failed) format='Could not read the game installation information' ;;
    ko:unsafe_shortcut_path) format='게임 바로가기 위치가 안전하지 않습니다' ;;
    en:unsafe_shortcut_path) format='The game shortcut path is unsafe' ;;
    ko:shortcut_conflict) format='같은 이름의 기존 파일이 있어 덮어쓰지 않았습니다: %s' ;;
    en:shortcut_conflict) format='An existing file has the same name and was not overwritten: %s' ;;
    ko:shortcut_created) format='%s 바로가기를 만들었습니다' ;;
    en:shortcut_created) format='Created a shortcut for %s' ;;
    ko:repairing_login) format='Steam 로그인 화면용 임시 데이터를 초기화하고 있습니다' ;;
    en:repairing_login) format='Resetting temporary data for the Steam login screen' ;;
    ko:owned_wrapper_not_found) format='이 설치 앱이 만든 Windows Steam을 찾을 수 없습니다' ;;
    en:owned_wrapper_not_found) format='The Windows Steam app created by this setup app was not found' ;;
    ko:unsafe_html_cache) format='Steam 임시 데이터 위치가 Wine 실행 공간 밖을 가리켜 중단했습니다' ;;
    en:unsafe_html_cache) format='Stopped because the Steam cache path points outside the Wine environment' ;;
    ko:login_repaired) format='로그인 화면을 복구했습니다. Steam이 다시 열렸습니다' ;;
    en:login_repaired) format='The login screen was repaired and Steam reopened' ;;
    ko:checking_requirements) format='이 Mac이 실행 조건을 만족하는지 확인하고 있습니다' ;;
    en:checking_requirements) format='Checking whether this Mac meets the requirements' ;;
    ko:apple_silicon_required) format='Apple Silicon Mac에서만 사용할 수 있습니다' ;;
    en:apple_silicon_required) format='An Apple Silicon Mac is required' ;;
    ko:macos_14_required) format='macOS Sonoma 14 이상이 필요합니다' ;;
    en:macos_14_required) format='macOS Sonoma 14 or later is required' ;;
    ko:installing_rosetta) format='Windows 앱 실행에 필요한 Apple Rosetta 2를 설치하고 있습니다' ;;
    en:installing_rosetta) format='Installing Apple Rosetta 2 for Windows app compatibility' ;;
    ko:rosetta_install_failed) format='Rosetta 2를 자동으로 설치하지 못했습니다' ;;
    en:rosetta_install_failed) format='Could not install Rosetta 2 automatically' ;;
    ko:rosetta_verify_failed) format='Rosetta 2 설치를 확인하지 못했습니다' ;;
    en:rosetta_verify_failed) format='Could not verify the Rosetta 2 installation' ;;
    ko:disk_space_required) format='설치 공간이 부족합니다. 최소 5GB를 확보해 주세요' ;;
    en:disk_space_required) format='Not enough storage space. Free at least 5 GB and try again' ;;
    ko:downloading_components) format='Sikarugir 공식 실행 엔진과 앱 틀을 내려받고 있습니다' ;;
    en:downloading_components) format='Downloading the official Sikarugir engine and app template' ;;
    ko:unsafe_download_path) format='다운로드 위치가 안전하지 않습니다: %s' ;;
    en:unsafe_download_path) format='The download path is unsafe: %s' ;;
    ko:download_failed) format='다운로드에 실패했습니다: %s' ;;
    en:download_failed) format='Download failed: %s' ;;
    ko:download_validation_failed) format='다운로드 파일 검증에 실패했습니다: %s' ;;
    en:download_validation_failed) format='Downloaded-file validation failed: %s' ;;
    ko:pinned_download_mismatch) format='다운로드 파일의 고정 버전 검증에 실패했습니다: %s' ;;
    en:pinned_download_mismatch) format='The downloaded file does not match the pinned version: %s' ;;
    ko:cached_download_mismatch) format='캐시 파일이 검증된 고정 버전과 다릅니다: %s' ;;
    en:cached_download_mismatch) format='The cached file does not match the verified pinned version: %s' ;;
    ko:runtime_engine) format='실행 엔진' ;;
    en:runtime_engine) format='Runtime engine' ;;
    ko:app_template) format='앱 틀' ;;
    en:app_template) format='App template' ;;
    ko:creating_wrapper) format='Windows Steam 전용 Mac 앱을 만들고 있습니다' ;;
    en:creating_wrapper) format='Creating the Mac app for Windows Steam' ;;
    ko:unsafe_wrapper_path) format='Steam.app 위치가 심볼릭 링크라 안전하게 진행할 수 없습니다' ;;
    en:unsafe_wrapper_path) format='Cannot continue safely because the Steam.app path is a symbolic link' ;;
    ko:unowned_wrapper) format='기존 Steam.app은 이 설치 앱이 만든 것으로 확인되지 않아 변경하지 않았습니다' ;;
    en:unowned_wrapper) format='The existing Steam.app was not created by this setup app and was left unchanged' ;;
    ko:wrapper_create_failed) format='Windows Steam 앱을 안전하게 생성하지 못했습니다' ;;
    en:wrapper_create_failed) format='Could not safely create the Windows Steam app' ;;
    ko:generated_launcher_missing) format='생성된 Sikarugir 실행 파일을 찾을 수 없습니다' ;;
    en:generated_launcher_missing) format='The generated Sikarugir launcher was not found' ;;
    ko:preparing_windows) format='Windows 실행 공간을 처음 한 번 준비하고 있습니다' ;;
    en:preparing_windows) format='Preparing the Windows environment for the first time' ;;
    ko:windows_environment_failed) format='Windows 실행 공간 생성에 실패했습니다' ;;
    en:windows_environment_failed) format='Could not create the Windows environment' ;;
    ko:steam_installer_instruction) format='Windows Steam 설치 창이 열리면 기본 설정으로 설치해 주세요' ;;
    en:steam_installer_instruction) format='When the Windows Steam installer opens, install using the default options' ;;
    ko:unsafe_steam_setup_symlink) format='Steam 설치 파일 위치가 심볼릭 링크라 중단했습니다' ;;
    en:unsafe_steam_setup_symlink) format='Stopped because the Steam installer path is a symbolic link' ;;
    ko:unsafe_steam_setup_directory) format='Steam 설치 파일 위치가 폴더라 중단했습니다' ;;
    en:unsafe_steam_setup_directory) format='Stopped because the Steam installer path is a directory' ;;
    ko:steam_setup_validation_failed) format='새로 받은 Steam 설치 파일 검증에 실패했습니다' ;;
    en:steam_setup_validation_failed) format='The newly downloaded Steam installer failed validation' ;;
    ko:steam_install_confirmed) format='Steam 설치를 확인했습니다. 첫 실행을 정리하고 최종 설정을 적용합니다' ;;
    en:steam_install_confirmed) format='Steam installation detected. Cleaning up the first launch and applying final settings' ;;
    ko:steam_install_timeout) format='Steam 설치 대기 시간이 초과됐습니다' ;;
    en:steam_install_timeout) format='Timed out while waiting for the Steam installation' ;;
    ko:steam_install_failed) format='Steam 설치를 완료하지 못했습니다. 설치 경로는 기본값을 사용해 주세요' ;;
    en:steam_install_failed) format='Steam installation was not completed. Use the default installation path' ;;
    ko:applying_configuration) format='D3DMetal과 실행 설정을 자동으로 적용하고 있습니다' ;;
    en:applying_configuration) format='Applying D3DMetal and launch settings' ;;
    ko:steam_plist_missing) format='Steam 앱 설정 파일을 찾을 수 없습니다' ;;
    en:steam_plist_missing) format='The Steam app configuration file was not found' ;;
    ko:d3dmetal_verify_failed) format='D3DMetal 설정 확인에 실패했습니다' ;;
    en:d3dmetal_verify_failed) format='Could not verify the D3DMetal configuration' ;;
    ko:ready_to_launch) format='준비가 끝났습니다. Windows Steam을 실행합니다' ;;
    en:ready_to_launch) format='Setup is complete. Starting Windows Steam' ;;
    ko:shortcut_steam_missing) format='Windows Steam이 설치되어 있지 않습니다' ;;
    en:shortcut_steam_missing) format='Windows Steam is not installed' ;;
    ko:shortcut_steam_start_failed) format='Windows Steam을 시작하지 못했습니다' ;;
    en:shortcut_steam_start_failed) format='Could not start Windows Steam' ;;
    ko:shortcut_game_start_failed) format='Windows Steam에서 게임을 시작하지 못했습니다' ;;
    en:shortcut_game_start_failed) format='Could not start the game in Windows Steam' ;;
    *) format="$key" ;;
  esac

  printf "$format" "$@"
}
