// ハイスコアをブラウザの localStorage に読み書きする。
// localStorage が使えない環境（プライベートブラウズ・保存の禁止など）では、
// 例外を外に出さずに 0 を返し、保存はあきらめる（ゲームは止めない）。

const KEY = "ai-invaders:high-score";

function storage(): Storage | null {
  try {
    // 参照するだけで例外になるブラウザがあるため、try の中で触る
    return window.localStorage;
  } catch {
    return null;
  }
}

export function loadHighScore(): number {
  try {
    const raw = storage()?.getItem(KEY);
    const n = raw == null ? 0 : Number(raw);
    return Number.isInteger(n) && n > 0 ? n : 0;
  } catch {
    return 0;
  }
}

export function saveHighScore(score: number): void {
  try {
    storage()?.setItem(KEY, String(score));
  } catch {
    // 容量超過や保存の禁止では何もしない
  }
}
