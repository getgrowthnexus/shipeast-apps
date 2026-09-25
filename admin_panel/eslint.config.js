// ESLint flat config for the admin panel (P0-03).
//
// The panel is plain ES modules loaded straight into the browser — no bundler,
// no transpile step. That means a syntax error or a typo'd identifier ships to
// production and blanks the page, with no build step to catch it. This config
// is the missing build step.
//
// Scope is deliberately narrow: correctness only, not style. `app.js` is
// 1,400+ lines of terse, consistent, working code; a stylistic ruleset would
// produce hundreds of findings that nobody will action and would train the
// team to ignore the linter.

export default [
  {
    files: ['**/*.js'],
    ignores: ['eslint.config.js'],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: 'module',
      globals: {
        window: 'readonly',
        document: 'readonly',
        console: 'readonly',
        navigator: 'readonly',
        location: 'readonly',
        localStorage: 'readonly',
        sessionStorage: 'readonly',
        setTimeout: 'readonly',
        clearTimeout: 'readonly',
        setInterval: 'readonly',
        clearInterval: 'readonly',
        requestAnimationFrame: 'readonly',
        performance: 'readonly',
        matchMedia: 'readonly',
        fetch: 'readonly',
        FormData: 'readonly',
        Blob: 'readonly',
        File: 'readonly',
        FileReader: 'readonly',
        Image: 'readonly',
        URL: 'readonly',
        CustomEvent: 'readonly',
        Event: 'readonly',
        MutationObserver: 'readonly',
        // Web Crypto. Used to generate a driver's initial app password
        // (generatePassword in app.js) — Math.random is not acceptable for
        // anything that becomes a credential.
        crypto: 'readonly',
        Uint32Array: 'readonly'
      }
    },
    rules: {
      'no-undef': 'error',
      'no-dupe-keys': 'error',
      'no-dupe-args': 'error',
      'no-duplicate-case': 'error',
      'no-unreachable': 'error',
      'no-cond-assign': 'error',
      'no-constant-condition': 'error',
      'no-func-assign': 'error',
      'no-obj-calls': 'error',
      'no-sparse-arrays': 'error',
      'use-isnan': 'error',
      'valid-typeof': 'error',
      'no-self-assign': 'error',
      'no-self-compare': 'error',
      'no-unsafe-negation': 'error',
      'no-unsafe-finally': 'error',
      'no-fallthrough': 'error',
      'no-unused-vars': ['error', { args: 'none', varsIgnorePattern: '^_' }]
    }
  }
];
