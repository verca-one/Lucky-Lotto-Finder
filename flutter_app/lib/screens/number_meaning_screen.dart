import 'package:flutter/material.dart';

class NumberMeaningContent extends StatefulWidget {
  const NumberMeaningContent({super.key});

  @override
  State<NumberMeaningContent> createState() => _NumberMeaningContentState();
}

class _NumberMeaningContentState extends State<NumberMeaningContent> {
  String _searchQuery = '';

  static const List<_NumberInfo> _allNumbers = [
    _NumberInfo(1, '시작, 기회, 대통령, 태극기, 할아버지', '7183 시작점', [0xFFFFC107]),
    _NumberInfo(2, '인간관계, 어머니, 안개, 비행기, 얼음', '대칭수/연결', [0xFFFFC107]),
    _NumberInfo(3, '선택, 인형, 귀신, 왕관, 노란색', '초압축 유도수', [0xFFFFC107]),
    _NumberInfo(4, '안정, 죽음, 개미, 수족관, 벌레', '사방위/기초', [0xFFFFC107]),
    _NumberInfo(5, '변화, 오곡, 쥐, 장모, 분식', '유동적 흐름', [0xFFFFC107]),
    _NumberInfo(6, '금전, 공무원, 공원, 비구니, 철도', '실속수', [0xFFFFC107]),
    _NumberInfo(7, '행운, 무지개, 금, 신의 수, 고가도로', '1218회 고정수', [0xFFFFC107]),
    _NumberInfo(8, '재물운, 산, 자전거, 거북이, 운전수', '7183 순환수', [0xFFFFC107]),
    _NumberInfo(9, '완성, 하늘, 신발, 머리카락, 대머리', '끝수 마무리', [0xFFFFC107]),
    _NumberInfo(10, '기회의 수, 고향집, 시계, 군대, 지갑', '십코딩 시작', [0xFFFFC107]),
    _NumberInfo(11, '쌍둥이, 길, 대나무, 축구선수, 다리', '병렬 구조', [0xFF2196F3]),
    _NumberInfo(12, '가족, 돼지, 고양이, 가구, 아이', '화합의 수', [0xFF2196F3]),
    _NumberInfo(13, '죽음(변화), 공동묘지, 영정사진, 속옷', '변곡점', [0xFF2196F3]),
    _NumberInfo(14, '불안정, 자동차, 감, 화장실, 사냥꾼', '허수 경계', [0xFF2196F3]),
    _NumberInfo(15, '보름달, 싸움, 도끼, 농기구, 망치', '테마수 코어', [0xFF2196F3]),
    _NumberInfo(16, '책, 문서, 어깨, 고등학교, 가슴', '지식/기록', [0xFF2196F3]),
    _NumberInfo(17, '조심, 칼, 물고기, 이불, 절터', '경고수', [0xFF2196F3]),
    _NumberInfo(18, '예술, 아버지, 전공자, 콩나물, 사진', '실질 권위', [0xFF2196F3]),
    _NumberInfo(19, '기쁜 소식, 소방차, 빨간색, 일기예보', '핵심 테마수', [0xFF2196F3]),
    _NumberInfo(20, '카메라, 오렌지색, 담배, 늙은 친구', '휴식/정지', [0xFF2196F3]),
    _NumberInfo(21, '성공과 성취, 높은 산, 청소년, 지도', '핵심 테마수', [0xFFF44336]),
    _NumberInfo(22, '공항, 신비함, 결혼, 수갑, 미로', '구속/해방', [0xFFF44336]),
    _NumberInfo(23, '기술자, 긴 머리, 케이블카, 정보원', '앵커숫자 (유지)', [0xFFF44336]),
    _NumberInfo(24, '이사, 술, 배우, 와인, 용', '앵커숫자 (연결)', [0xFFF44336]),
    _NumberInfo(25, '축복, 꽃, 향기, 연인, 결혼식', '확장 지원', [0xFFF44336]),
    _NumberInfo(26, '자매, 신부, 집, 교회, 바늘', '종교/여성', [0xFFF44336]),
    _NumberInfo(27, '보물, 금, 가치 있는 물건, 아파트', '강력 앵커숫자', [0xFFF44336]),
    _NumberInfo(28, '보석, 반지, 상자, 컴퓨터, 냉장고', '실물 자산', [0xFFF44336]),
    _NumberInfo(29, '철갑, 갑옷, 활, 화살, 갈비', '방어/공격', [0xFFF44336]),
    _NumberInfo(30, '컵, 솥, 가방, 냄비, 닻', '반동확장 대기', [0xFFF44336]),
    _NumberInfo(31, '사슴, 산 정상, 강연, 신분증', '높은 위치', [0xFF616161]),
    _NumberInfo(32, '쌀, 논밭, 과일, 채소, 수표', '수확의 수', [0xFF616161]),
    _NumberInfo(33, '도전, 용, 개, 어둠, 산삼', '확장 돌파수', [0xFF616161]),
    _NumberInfo(34, '문, 커튼, 현관, 입구, 공연장', '새로운 구간', [0xFF616161]),
    _NumberInfo(35, '군인, 게, 논, 밭, 넓은 들판', '확장 지지선', [0xFF616161]),
    _NumberInfo(36, '외국인, 동전, 버스, 돈다발, 화장', '교류/변화', [0xFF616161]),
    _NumberInfo(37, '불, 빛, 램프, 주사기, 포도', '에너지 분출', [0xFF616161]),
    _NumberInfo(38, '거울, 침대, 가구, 장롱, 닻', '반동확장 종착', [0xFF616161]),
    _NumberInfo(39, '빵, 음식, 잔치, 국수, 바가지', '풍요/정리', [0xFF616161]),
    _NumberInfo(40, '돌, 다리, 병원, 의사, 수박', '단단한 고정', [0xFF616161]),
    _NumberInfo(41, '재정 점검, 연예인, 부적, 간호사', '보너스/이월', [0xFF4CAF50]),
    _NumberInfo(42, '편지, 우체국, 기차, 전철, 인쇄물', '소식 전달', [0xFF4CAF50]),
    _NumberInfo(43, '무덤, 고기, 식사, 항아리, 밧줄', '과거 정리', [0xFF4CAF50]),
    _NumberInfo(44, '바다, 깊은 물, 계단, 저수지, 무너짐', '거대 확장', [0xFF4CAF50]),
    _NumberInfo(45, '마지막, 귀신, 조상, 영혼, 굴뚝', '사이클 완성', [0xFF4CAF50]),
  ];

  List<_NumberInfo> get _filtered {
    if (_searchQuery.isEmpty) return _allNumbers;
    return _allNumbers.where((n) {
      return n.number.toString().contains(_searchQuery) ||
          n.meaning.contains(_searchQuery) ||
          n.note.contains(_searchQuery);
    }).toList();
  }

  Color _ballColor(int number) {
    if (number <= 10) return Colors.yellow.shade700;
    if (number <= 20) return Colors.blue;
    if (number <= 30) return Colors.red;
    if (number <= 40) return Colors.grey.shade700;
    return Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return Column(
      children: [
        // 검색
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: '번호 또는 키워드 검색',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ),
        // 구간 범례
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _legendChip('1~10', Colors.yellow.shade700),
              _legendChip('11~20', Colors.blue),
              _legendChip('21~30', Colors.red),
              _legendChip('31~40', Colors.grey.shade700),
              _legendChip('41~45', Colors.green),
            ],
          ),
        ),
        const SizedBox(height: 4),
        // 목록
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final info = list[index];
              final color = _ballColor(info.number);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 공
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${info.number}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 의미
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.meaning,
                            style: const TextStyle(fontSize: 13, height: 1.3),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              info.note,
                              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _legendChip(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }
}

class _NumberInfo {
  final int number;
  final String meaning;
  final String note;
  final List<int> colorCodes;

  const _NumberInfo(this.number, this.meaning, this.note, this.colorCodes);
}
