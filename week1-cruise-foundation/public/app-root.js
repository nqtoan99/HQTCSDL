(() => {
  const template = document.getElementById('aurora-shell');
  const mount = document.getElementById('aurora-root');
  if (!template || !mount || !window.React || !window.ReactDOM?.createRoot) return;

  const root = window.ReactDOM.createRoot(mount);
  window.ReactDOM.flushSync(() => {
    root.render(window.React.createElement('div', {
      id: 'aurora-app-shell',
      dangerouslySetInnerHTML: { __html: template.innerHTML },
    }));
  });
})();
