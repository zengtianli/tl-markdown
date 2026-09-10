// CodeMirror already creates widgets near its viewport. Do not put rendering
// behind IntersectionObserver: an inactive WKWebView may never deliver it.
export class DiagramError extends Error {
  constructor(message, code) { super(message); this.code = code; }
}

export function bounded(work, milliseconds, message) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new DiagramError(message, 'timeout')), milliseconds);
    Promise.resolve().then(work).then(resolve, reject).finally(() => clearTimeout(timer));
  });
}

export function mermaidLoader(scope = window, document = scope.document, timeout = 10000) {
  let pending;
  return function load() {
    if (typeof scope.TLMermaid?.render === 'function') return Promise.resolve(scope.TLMermaid);
    if (pending) return pending;
    const script = document.createElement('script');
    script.src = 'mermaid.js';
    pending = bounded(() => new Promise((resolve, reject) => {
      script.onload = () => typeof scope.TLMermaid?.render === 'function'
        ? resolve(scope.TLMermaid)
        : reject(new DiagramError('本地图表组件不完整', 'load'));
      script.onerror = () => reject(new DiagramError('本地图表组件加载失败', 'load'));
      document.head.append(script);
    }), timeout, '本地图表组件加载超时').catch(error => {
      pending = undefined;
      script.remove();
      throw error;
    });
    return pending;
  };
}

let counter = 0;
export function drawDiagram({element, source, load, sanitize, measure, timeout = 15000}) {
  let disposed = false;
  element.textContent = '正在绘制图表…';
  element.dataset.diagramState = 'loading';
  // The microtask runs after the widget has been attached, without waiting for
  // visibility/animation-frame delivery from an inactive host window.
  const done = Promise.resolve().then(async () => {
    if (disposed) return;
    const api = await load();
    if (disposed) return;
    const {svg} = await bounded(() => api.render('tlm-' + (++counter), source), timeout, '图表绘制超时，请点击源码后重试');
    if (!svg?.includes('<svg')) throw new DiagramError('图表组件未返回图像', 'render');
    if (!disposed) {
      element.innerHTML = sanitize(svg);
      element.dataset.diagramState = 'ready';
      measure();
    }
  }).catch(error => {
    if (disposed) return;
    const message = error instanceof DiagramError ? error.message : '图表无法绘制，请点击检查源码';
    element.textContent = message + '\n' + source;
    element.classList.add('render-error');
    element.dataset.diagramState = 'error';
    measure();
  });
  return {done, dispose() { disposed = true; }};
}
