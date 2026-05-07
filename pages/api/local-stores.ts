import { NextRequest, NextResponse } from 'next/server';
import * as fs from 'fs';
import * as path from 'path';

export async function GET(request: NextRequest) {
  try {
    // 크롤링 데이터 폴더 경로
    const crawlingDir = path.join(process.cwd(), 'data', 'crawling');

    let storesData: any[] = [];

    // winner_stores.json 읽기 (모든 데이터)
    const winnerStoresPath = path.join(crawlingDir, 'winner_stores.json');

    console.log('파일 경로:', winnerStoresPath);
    console.log('파일 존재:', fs.existsSync(winnerStoresPath));

    if (fs.existsSync(winnerStoresPath)) {
      const data = fs.readFileSync(winnerStoresPath, 'utf-8');
      storesData = JSON.parse(data);
      console.log('데이터 로드 성공:', storesData.length);
    } else {
      console.warn('파일을 찾을 수 없습니다:', winnerStoresPath);
    }

    return NextResponse.json(storesData);
  } catch (error) {
    console.error('로컬 스토어 데이터 로드 실패:', error);
    return NextResponse.json(
      { error: '데이터 로드 실패', details: String(error) },
      { status: 500 }
    );
  }
}
