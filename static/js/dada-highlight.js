/**
 * Dada syntax highlighter
 * Uses Chroma CSS classes for consistent styling with other code blocks
 */
(function() {
  'use strict';

  function highlightDada() {
    const blocks = document.querySelectorAll('code.language-dada');

    blocks.forEach(block => {
      const keywords = (block.dataset.dadaKeywords || 'let').split(',');
      const types = (block.dataset.dadaTypes || 'String').split(',');

      const code = block.textContent;
      const highlighted = highlightCode(code, keywords, types);
      block.innerHTML = highlighted;
    });
  }

  function escapeHtml(text) {
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function highlightCode(code, keywords, types) {
    // Split code into tokens
    const tokens = [];
    let pos = 0;

    // Tokenize patterns (order matters!)
    const tokenPatterns = [
      // Comments: both // and # style
      { type: 'comment', regex: /^(\/\/[^\n]*|#[^\n]*)/ },

      // String literals
      { type: 'string', regex: /^"([^"]*)"/ },

      // Numbers
      { type: 'number', regex: /^(\d+(?:\.\d+)?)/ },

      // Identifiers and keywords
      { type: 'ident', regex: /^([a-zA-Z_][a-zA-Z0-9_]*)/ },

      // Punctuation and operators
      { type: 'punct', regex: /^([(){}[\]:;,.])/ },
      { type: 'op', regex: /^(=)/ },

      // Whitespace
      { type: 'space', regex: /^(\s+)/ },
    ];

    while (pos < code.length) {
      let matched = false;

      for (const pattern of tokenPatterns) {
        const match = code.substring(pos).match(pattern.regex);
        if (match) {
          tokens.push({ type: pattern.type, text: match[0] });
          pos += match[0].length;
          matched = true;
          break;
        }
      }

      if (!matched) {
        // Unknown character, just add it
        tokens.push({ type: 'text', text: code[pos] });
        pos++;
      }
    }

    // Convert tokens to highlighted HTML
    let result = '';
    for (let i = 0; i < tokens.length; i++) {
      const token = tokens[i];
      const escaped = escapeHtml(token.text);

      if (token.type === 'comment') {
        result += '<span class="c1">' + escaped + '</span>';
      } else if (token.type === 'string') {
        // Handle string interpolation
        const stringContent = token.text.slice(1, -1); // Remove quotes
        const highlighted = stringContent.replace(/\{([^}]+)\}/g, function(match, expr) {
          return escapeHtml('{') + '<span class="n">' + escapeHtml(expr) + '</span>' + escapeHtml('}');
        });
        result += '<span class="s">&quot;' + highlighted + '&quot;</span>';
      } else if (token.type === 'number') {
        result += '<span class="mi">' + escaped + '</span>';
      } else if (token.type === 'ident') {
        // Check if it's a keyword, type, or function call
        const nextNonSpace = tokens.slice(i + 1).find(t => t.type !== 'space');

        if (keywords.includes(token.text)) {
          result += '<span class="k">' + escaped + '</span>';
        } else if (types.includes(token.text)) {
          result += '<span class="kt">' + escaped + '</span>';
        } else if (nextNonSpace && nextNonSpace.text === '(') {
          result += '<span class="nf">' + escaped + '</span>';
        } else {
          result += escaped;
        }
      } else if (token.type === 'punct') {
        result += '<span class="p">' + escaped + '</span>';
      } else if (token.type === 'op') {
        result += '<span class="o">' + escaped + '</span>';
      } else {
        result += escaped;
      }
    }

    return result;
  }

  // Run when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', highlightDada);
  } else {
    highlightDada();
  }
})();
