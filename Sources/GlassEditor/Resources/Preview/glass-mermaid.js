// Glass Power Tools — the Markdown preview's only script of its own (D35).
// Turns ```mermaid fences into diagrams with the bundled Mermaid. Strict security level: no
// click handlers, no HTML labels, nothing Mermaid itself would let a diagram execute.
(function () {
  var blocks = document.querySelectorAll('pre > code.language-mermaid');
  blocks.forEach(function (code) {
    var div = document.createElement('div');
    div.className = 'mermaid';
    div.textContent = code.textContent;
    code.parentElement.replaceWith(div);
  });
  if (!window.mermaid || blocks.length === 0) { return; }
  var dark = window.matchMedia('(prefers-color-scheme: dark)').matches;
  window.mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: dark ? 'dark' : 'default' });
  window.mermaid.run({ querySelector: '.mermaid' }).catch(function (error) {
    var note = document.createElement('p');
    note.className = 'mermaid-error';
    note.textContent = 'Mermaid: ' + (error && error.message ? error.message : error);
    document.body.appendChild(note);
  });
})();
