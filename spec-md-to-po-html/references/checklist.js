/* ===========================================================
   checkList.html 互動腳本
   產出 HTML 時把整段內聯到 <script> 標籤裡
   並把 {{ISSUE_KEY}} 替換成實際單號
   =========================================================== */

(function() {
  const ISSUE_KEY = '{{ISSUE_KEY}}';
  const STORAGE_KEY = 'po-checklist-' + ISSUE_KEY;

  /* ---------- 從 localStorage 還原 ---------- */
  function restore() {
    try {
      const saved = JSON.parse(localStorage.getItem(STORAGE_KEY) || '{}');
      Object.entries(saved).forEach(([q, v]) => {
        if (q.startsWith('A-')) {
          const cb = document.querySelector(
            'input[type="checkbox"][data-q="' + q + '"]'
          );
          if (cb) cb.checked = !!v;
        } else if (typeof v === 'string') {
          if (v.startsWith('C:')) {
            const r = document.querySelector(
              'input[type="radio"][data-q="' + q + '"][value="C"]'
            );
            const t = document.querySelector(
              'input.other-input[data-other="' + q + '"]'
            );
            if (r) r.checked = true;
            if (t) t.value = v.slice(2);
          } else {
            const r = document.querySelector(
              'input[type="radio"][data-q="' + q + '"][value="' + v + '"]'
            );
            if (r) r.checked = true;
          }
        }
      });
    } catch (e) { /* ignore */ }
  }

  /* ---------- 寫入 localStorage ---------- */
  function persist() {
    const data = {};
    document.querySelectorAll('input[type="radio"]:checked').forEach(function(r) {
      const q = r.getAttribute('data-q');
      if (r.value === 'C') {
        const t = document.querySelector(
          'input.other-input[data-other="' + q + '"]'
        );
        data[q] = 'C:' + (t ? t.value : '');
      } else {
        data[q] = r.value;
      }
    });
    document.querySelectorAll('input[type="checkbox"][data-q]').forEach(function(c) {
      data[c.getAttribute('data-q')] = c.checked;
    });
    localStorage.setItem(STORAGE_KEY, JSON.stringify(data));
  }

  /* ---------- 進度條 ---------- */
  function updateProgress() {
    const answered = new Set();
    document.querySelectorAll('input[type="radio"]:checked').forEach(function(r) {
      answered.add(r.getAttribute('data-q'));
    });
    const el = document.getElementById('answered-count');
    if (el) el.textContent = answered.size;
  }

  /* ---------- 組裝 Jira 回覆 Markdown ---------- */
  function buildReply() {
    const lines = ['## ' + ISSUE_KEY + ' PO 補問回覆', ''];
    const radios = {};

    document.querySelectorAll('input[type="radio"]:checked').forEach(function(r) {
      const q = r.getAttribute('data-q');
      let v = r.value;
      const span = r.parentElement.querySelector('span:not(.opt-label):not(.recommend)');
      const text = span ? span.textContent.trim().replace(/\s+/g, ' ').slice(0, 100) : '';
      if (v === 'C') {
        const other = document.querySelector(
          'input.other-input[data-other="' + q + '"]'
        );
        v = 'C. ' + (other && other.value ? other.value : '(未填)');
      } else {
        v = v + '. ' + text.replace(/^[A-Z]\.\s*/, '');
      }
      radios[q] = v;
    });

    Object.keys(radios).sort().forEach(function(q) {
      lines.push('- **' + q + '**: ' + radios[q]);
    });

    /* 未回答提醒 */
    const allQuestions = Array.from(
      document.querySelectorAll('input[type="radio"][data-q]')
    ).map(function(r) { return r.getAttribute('data-q'); });
    const unique = [...new Set(allQuestions)];
    const unanswered = unique.filter(function(q) { return !radios[q]; });
    if (unanswered.length) {
      lines.push('');
      lines.push('> ⚠️ 尚未回答:' + unanswered.join(', '));
    }

    /* AI 假設 */
    const aiCheckboxes = document.querySelectorAll('input[type="checkbox"][data-q]');
    if (aiCheckboxes.length) {
      lines.push('');
      lines.push('### AI 假設(勾選 = 同意)');
      aiCheckboxes.forEach(function(c) {
        const q = c.getAttribute('data-q');
        const sign = c.checked ? '✓ 同意' : '✗ 不同意';
        lines.push('- ' + q + ': ' + sign);
      });
    }

    return lines.join('\n');
  }

  /* ---------- 事件綁定 ---------- */
  document.querySelectorAll(
    'input[type="radio"], input[type="checkbox"], input.other-input'
  ).forEach(function(el) {
    el.addEventListener('change', function() { updateProgress(); persist(); });
    el.addEventListener('input', persist);
  });

  /* ---------- 複製按鈕 ---------- */
  const btnCopy = document.getElementById('btn-copy');
  if (btnCopy) {
    btnCopy.addEventListener('click', async function() {
      const text = buildReply();
      try {
        await navigator.clipboard.writeText(text);
        const toast = document.getElementById('toast');
        if (toast) {
          toast.classList.add('show');
          setTimeout(function() { toast.classList.remove('show'); }, 2500);
        }
      } catch (e) {
        alert('複製失敗,以下為內容:\n\n' + text);
      }
    });
  }

  /* ---------- 匯出 JSON ---------- */
  const btnExport = document.getElementById('btn-export');
  if (btnExport) {
    btnExport.addEventListener('click', function() {
      const data = {
        issue_key: ISSUE_KEY,
        answered_at: new Date().toISOString(),
        answers: {},
        assumptions: {}
      };
      document.querySelectorAll('input[type="radio"]:checked').forEach(function(r) {
        const q = r.getAttribute('data-q');
        if (r.value === 'C') {
          const t = document.querySelector(
            'input.other-input[data-other="' + q + '"]'
          );
          data.answers[q] = { choice: 'C', text: t ? t.value : '' };
        } else {
          data.answers[q] = { choice: r.value };
        }
      });
      document.querySelectorAll('input[type="checkbox"][data-q]').forEach(function(c) {
        data.assumptions[c.getAttribute('data-q')] = c.checked;
      });
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = ISSUE_KEY + '-checklist-answers.json';
      a.click();
      URL.revokeObjectURL(url);
    });
  }

  restore();
  updateProgress();
})();
