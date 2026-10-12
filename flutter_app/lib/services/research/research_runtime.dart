// 연구 엔진 실행 위치 — 연구 계산·저장은 서버(GitHub Actions)만 한다.
//
// 앱(관리자·일반 모두): serverWriter = false → 연구 결과를 계산·저장하지 않고 저장된 결과만 읽는다.
// 서버 파이프라인(tool/server/research_pipeline_test.dart): service_role 키로 초기화한 뒤 true 로 켠다.
class ResearchRuntime {
  ResearchRuntime._();

  /// true = 서버 파이프라인 (연구 결과 계산·DB 저장 허용)
  static bool serverWriter = false;
}
