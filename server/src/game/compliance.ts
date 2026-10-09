/* INSURE QUEST｜合規雷達規則引擎。
 * 依台灣保險招攬規範與金融消保法，即時偵測業務員話術中的違規或瑕疵。
 */

export type ComplianceLevel = 'pass' | 'warning' | 'violation';

export type ComplianceCode =
  | 'PROMISE_RETURN'        // 保證收益/穩賺不賠
  | 'FEAR_MONGERING'       // 恐嚇推銷/詛咒出事
  | 'MISLEADING_COMPARISON'// 不實比較/貶低同業或定存
  | 'UNDISCLOSED_RISK'     // 未揭露費用或風險
  | 'EARLY_PRESSURE'       // 未探詢需求即強推商品或逼問預算
  | 'INJECTION_ATTEMPT';   // 偵測到 Prompt 注入攻擊

export interface ComplianceIssue {
  code: ComplianceCode;
  quote: string;
  rule: string;
  suggestion: string;
}

export interface ComplianceData {
  level: ComplianceLevel;
  penalty: number;
  issues: ComplianceIssue[];
}

interface RulePattern {
  code: ComplianceCode;
  level: ComplianceLevel;
  penalty: number;
  pattern: RegExp;
  rule: string;
  suggestion: string;
}

const COMPLIANCE_PATTERNS: RulePattern[] = [
  {
    code: 'INJECTION_ATTEMPT',
    level: 'violation',
    penalty: -25,
    pattern: /(ignore (all )?previous|system prompt|你現在是|忘記你的設定|忽略前述指令|無視指令|角色扮演指令|reveal system)/i,
    rule: '面談系統防護：輸入內容與客戶面談無關',
    suggestion: '請專注於客戶需求訪談，勿輸入無關指令',
  },
  {
    code: 'PROMISE_RETURN',
    level: 'violation',
    penalty: -20,
    // 否定語境（「無法保證收益」「不能說穩賺」）是正確的揭露，不算違規
    pattern: /(?<!(不|無法|不能|沒辦法|沒有人能|不敢|不會)(說|講|承諾|給你|跟你說)?)(保證(獲利|收益|賺|理賠|保本|不賠|報酬|回本)|穩賺(不賠)?|一定賺|絕(對|不會)虧|比定存(好|高))/u,
    rule: '保險業招攬廣告自律規範：不得為保證獲利或保本之宣傳',
    suggestion: '說明各商品之風險屬性與條款，避免保證用語',
  },
  {
    code: 'FEAR_MONGERING',
    level: 'violation',
    penalty: -20,
    pattern: /(?<!(不|不會|不要))(不買會後悔|出事就完(了|蛋)|一定會後悔|完蛋了|等死|後悔莫及)/u,
    rule: '金融消費者保護法：不得以誇大、恐嚇方式招攬',
    suggestion: '以同理心探詢客戶擔憂，勿使用恐嚇式語言',
  },
  {
    code: 'MISLEADING_COMPARISON',
    level: 'violation',
    penalty: -15,
    pattern: /(比定存強|定存很蠢|別家(保險)?都很爛|別家會倒)/u,
    rule: '保險業招攬廣告自律規範：不得為不當比較或貶低同業',
    suggestion: '客觀說明商品特色，尊重客戶原有財務規劃',
  },
  {
    code: 'EARLY_PRESSURE',
    level: 'warning',
    penalty: -8,
    pattern: /(只剩今天|現在不簽就沒了|立刻簽|馬上決定|今天不買就沒了)/u,
    rule: '金融服務業公平待客原則：應充分說明並給予客戶考慮時間',
    suggestion: '給予客戶充分思考時間，先確認需求再討論促成',
  },
];

/** 規則版合規雷達分析 */
export function ruleCompliance(text: string): ComplianceData {
  const issues: ComplianceIssue[] = [];
  let worstLevel: ComplianceLevel = 'pass';
  let minPenalty = 0;

  for (const item of COMPLIANCE_PATTERNS) {
    const match = text.match(item.pattern);
    if (match) {
      issues.push({
        code: item.code,
        quote: match[0].slice(0, 15),
        rule: item.rule,
        suggestion: item.suggestion,
      });

      if (item.level === 'violation') {
        worstLevel = 'violation';
      } else if (item.level === 'warning' && worstLevel !== 'violation') {
        worstLevel = 'warning';
      }

      minPenalty = Math.min(minPenalty, item.penalty);
    }
  }

  return {
    level: worstLevel,
    penalty: minPenalty,
    issues,
  };
}

const LEVEL_SEVERITY: Record<ComplianceLevel, number> = {
  pass: 0,
  warning: 1,
  violation: 2,
};

/** 合併規則版與 AI 版的合規判讀：取較嚴重者與扣分較多者 */
export function mergeCompliance(ruleComp: ComplianceData, aiComp?: ComplianceData | null): ComplianceData {
  if (!aiComp) return ruleComp;

  const level = LEVEL_SEVERITY[ruleComp.level] >= LEVEL_SEVERITY[aiComp.level]
    ? ruleComp.level
    : aiComp.level;

  const penalty = Math.min(ruleComp.penalty, aiComp.penalty);

  // 合併 issues，依 code 去重
  const seenCodes = new Set<string>();
  const mergedIssues: ComplianceIssue[] = [];
  for (const issue of [...ruleComp.issues, ...aiComp.issues]) {
    if (!seenCodes.has(issue.code)) {
      seenCodes.add(issue.code);
      mergedIssues.push(issue);
    }
  }

  return {
    level,
    penalty: Math.max(-25, Math.min(0, penalty)),
    issues: mergedIssues,
  };
}

/** AI 只能引用這些真實存在的規範名稱（不寫條號，避免引用錯誤條文） */
export const RULE_BY_CODE: Record<ComplianceCode, string> = {
  PROMISE_RETURN: '保險業招攬廣告自律規範：不得為保證獲利或保本之宣傳',
  FEAR_MONGERING: '金融消費者保護法：不得以誇大、恐嚇方式招攬',
  MISLEADING_COMPARISON: '保險業招攬廣告自律規範：不得為不當比較或貶低同業',
  UNDISCLOSED_RISK: '金融消費者保護法：應充分說明商品重要內容與風險',
  EARLY_PRESSURE: '金融服務業公平待客原則：應充分說明並給予客戶考慮時間',
  INJECTION_ATTEMPT: '面談系統防護：輸入內容與客戶面談無關',
};
