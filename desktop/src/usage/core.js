/* Provider response normalization, shared with the native Mac app via JavaScriptCore.
   Output is an allowlist: no account identifiers, credentials or server messages. */
(function (root) {
  'use strict';
  const providers = [
    { id: 'codex', name: 'Codex', kind: 'Plan usage', url: 'https://chatgpt.com/backend-api/wham/usage', guide: 'Sign in with Codex on this computer.' },
    { id: 'claude', name: 'Claude', kind: 'Plan usage', url: 'https://api.anthropic.com/api/oauth/usage', guide: 'Sign in with Claude Code on this computer.' },
    { id: 'grok', name: 'Grok', kind: 'Plan usage', url: 'https://cli-chat-proxy.grok.com/v1/billing?format=credits', guide: 'Sign in with Grok Build on this computer.' },
    { id: 'cursor', name: 'Cursor', kind: 'Plan usage', url: 'https://cursor.com/api/usage-summary', guide: 'Sign in with Cursor or cursor-agent on this computer.' },
    { id: 'deepseek', name: 'DeepSeek', kind: 'API balance', url: 'https://api.deepseek.com/user/balance', guide: 'Add a DeepSeek API key below.' },
    { id: 'openrouter', name: 'OpenRouter', kind: 'API balance', url: 'https://openrouter.ai/api/v1/credits', guide: 'Add an OpenRouter key with credits access below.' }
  ];
  function number(value) {
    if (typeof value !== 'number' && !(typeof value === 'string' && value.trim())) return null;
    const n = Number(value); return Number.isFinite(n) ? n : null;
  }
  function time(value) {
    const n = number(value);
    if (n !== null) return n > 0 ? (n < 1e11 ? n * 1000 : n) : null;
    const parsed = typeof value === 'string' ? Date.parse(value) : NaN;
    return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
  }
  function normalize(id, data) {
    if (!providers.some(p => p.id === id) || !data || typeof data !== 'object' || Array.isArray(data)) throw Error('Unsupported response');
    const meters = [], balances = [];
    const add = (label, used, reset) => { const n = number(used); if (n === null || n < 0) return; const percent = Math.min(100, n); meters.push({ label, used: percent, remaining: 100 - percent, resetsAt: time(reset) }); };
    const money = (currency, value) => { const n = number(value); if (['USD','CNY'].includes(currency) && n !== null) balances.push({ currency, amount: n }); };
    if (id === 'codex') {
      for (const [key, fallback] of [['primary_window','Session'],['secondary_window','Weekly']]) {
        const w = data.rate_limit && data.rate_limit[key];
        if (w) { const minutes = number(w.limit_window_seconds); const label = minutes === 18000 ? '5 hours' : minutes === 604800 ? 'Weekly' : fallback; add(label, w.used_percent, w.reset_at); }
      }
    } else if (id === 'claude') {
      for (const [key,label] of [['five_hour','5 hours'],['seven_day','Weekly'],['seven_day_sonnet','Sonnet weekly'],['seven_day_opus','Opus weekly'],['seven_day_fable','Fable weekly'],['fable_weekly','Fable weekly']]) {
        const w = data[key]; if (w && !meters.some(m => m.label === label)) add(label,w.utilization === undefined ? w.used_percentage : w.utilization,w.resets_at);
      }
      if (Array.isArray(data.limits)) for (const w of data.limits) if (w.kind === 'weekly_scoped' && w.scope && w.scope.model && String(w.scope.model.display_name).toLowerCase() === 'fable' && !meters.some(m=>m.label==='Fable weekly')) add('Fable weekly',w.percent,w.resets_at);
    } else if (id === 'grok') {
      const d = data.config || data, reset = (d.currentPeriod && d.currentPeriod.end) || d.billingPeriodEnd;
      if (number(d.creditUsagePercent) !== null) add('Weekly',d.creditUsagePercent,reset);
      else { const used = number(d.used && d.used.val), limit = number(d.monthlyLimit && d.monthlyLimit.val); if (used !== null && limit !== null && limit > 0) add('Monthly',100*used/limit,reset); }
    } else if (id === 'cursor') {
      const p = data.individualUsage && data.individualUsage.plan;
      if (p && p.enabled !== false) {
        add('Cursor Models',p.autoPercentUsed,data.billingCycleEnd); add('Other Models',p.apiPercentUsed,data.billingCycleEnd);
        const used=number(p.used), limit=number(p.limit);
        add('Monthly',p.totalPercentUsed === undefined && used !== null && limit > 0 ? used/limit*100 : p.totalPercentUsed,data.billingCycleEnd);
      }
      const p2=data.individualUsage && data.individualUsage.onDemand;
      if (p2 && p2.enabled === true) { const used=number(p2.used), limit=number(p2.limit); if (used!==null && limit>0) add('On-demand cap',used/limit*100,data.billingCycleEnd); }
    } else if (id === 'deepseek') {
      if (Array.isArray(data.balance_infos)) for (const b of data.balance_infos) money(b.currency,b.total_balance);
    } else if (id === 'openrouter') {
      const d=data.data || {}, credits=number(d.total_credits), used=number(d.total_usage);
      if (credits!==null && used!==null) money('USD',credits-used);
    }
    if (!meters.length && !balances.length) throw Error('No supported quota fields');
    return { meters, balances };
  }
  const api = { providers, normalize, number, time };
  root.UsageCore = api;
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
})(typeof globalThis === 'object' ? globalThis : this);
