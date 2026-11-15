// Every vertical drag on the terminal is captured (preventDefault) and
// translated into wheel events for xterm/tmux. No at-top detection, no
// release to the browser. Taps pass through untouched (6px threshold,
// passive touchstart) so links stay clickable.
(function () {
  var DRAG_THRESHOLD = 6;  // px of jitter tolerated before treating as scroll
  var PX_PER_LINE = 12;    // finger travel per scrolled line

  // mobile UA (same patterns as the proxy's routing): 2px transparent
  // scrollbar + no terminal padding, so the fit addon gets the full width
  if (/iPhone|iPad|Android|Mobile/.test(navigator.userAgent)) {
    document.documentElement.classList.add('ttyd-patch-mobile');
  }

  // viewport-fit=cover is required for Android (15+) / edge-to-edge apps to
  // report the gesture nav bar via env(safe-area-inset-bottom); without it the
  // inset reads 0 and the bottom terminal row slides under the gesture pill.
  // The height calc below compensates for the cover extension.
  var meta = document.querySelector('meta[name="viewport"]');
  if (meta && meta.content.indexOf('viewport-fit=cover') === -1) {
    meta.content += ', viewport-fit=cover';
  }

  // Scrollbar painting is CSS-only (see inject.css). xterm measures
  // scrollBarWidth = viewport.offsetWidth - scrollArea.offsetWidth || 15;
  // on overlay-scrollbar platforms (Android/iOS) that measurement is 0 and
  // the ||15 fallback reserves 15px of phantom width, so fitToVisualViewport
  // resets it to 0 before each refit (see below).

  // measure the bottom safe-area inset (Android gesture bar / iOS home bar).
  // On Android the inset is only reported in the TOP frame's context (the HA
  // app runs edge-to-edge), so probe both documents and take the max.
  function probeInset(doc) {
    var probe = doc.createElement('div');
    probe.style.cssText =
      'position:fixed;bottom:0;left:0;width:0;visibility:hidden;' +
      'height:env(safe-area-inset-bottom, 0px);';
    doc.body.appendChild(probe);
    var v = probe.getBoundingClientRect().height;
    probe.remove();
    return v;
  }
  function bottomInset() {
    var v = probeInset(document);
    try {
      var top = topWindow();
      if (top && top.document && top.document.body) {
        v = Math.max(v, probeInset(top.document));
      }
    } catch (e) {}
    return v;
  }

  var screenEl = null;
  var startY = null, lastY = null, isDragging = false, acc = 0;

  function getScreen() {
    if (!screenEl || !screenEl.isConnected) {
      screenEl = document.querySelector('.xterm-screen');
    }
    return screenEl;
  }

  document.addEventListener('touchstart', function (e) {
    if (e.touches.length !== 1) return;
    startY = lastY = e.touches[0].clientY;
    isDragging = false;
    acc = 0;
  }, { passive: true, capture: true });

  document.addEventListener('touchmove', function (e) {
    if (e.touches.length !== 1 || lastY === null) return;
    var el = getScreen();
    if (!el) return;
    var y = e.touches[0].clientY;
    if (!isDragging) {
      if (Math.abs(y - startY) < DRAG_THRESHOLD) return;
      isDragging = true;
    }
    var deltaY = lastY - y;
    lastY = y;

    e.preventDefault();
    acc += deltaY;
    if (Math.abs(acc) >= PX_PER_LINE) {
      var lines = Math.trunc(acc / PX_PER_LINE);
      acc -= lines * PX_PER_LINE;
      el.dispatchEvent(new WheelEvent('wheel', {
        deltaY: lines,
        deltaMode: WheelEvent.DOM_DELTA_LINE,
        clientX: e.touches[0].clientX,
        clientY: e.touches[0].clientY,
        bubbles: true,
        cancelable: true
      }));
      console.log('ttyd-patch wheel lines=' + lines);
    }
  }, { passive: false, capture: true });

  document.addEventListener('touchend', function () {
    startY = lastY = null;
    isDragging = false;
  }, { passive: true, capture: true });

  // virtual keyboard: on Android the keyboard resizes the TOP-LEVEL window's
  // visual viewport, not the ingress iframe's (our own visualViewport and
  // innerHeight stay frozen inside the iframe). The ingress iframe is
  // same-origin with the HA frontend, so read window.top.visualViewport when
  // accessible. Cut the terminal off at that height so the input line stays
  // above the keyboard, then re-dispatch resize so ttyd's fitAddon refits.
  function topWindow() {
    try {
      if (window.top && window.top !== window && window.top.visualViewport) return window.top;
    } catch (e) { /* cross-origin: fall back to own viewport */ }
    return null;
  }

  function probeInsetLR(doc) {
    var probe = doc.createElement('div');
    probe.style.cssText =
      'position:fixed;top:0;left:0;height:0;visibility:hidden;' +
      'width:env(safe-area-inset-left, 0px);';
    doc.body.appendChild(probe);
    var l = probe.getBoundingClientRect().width;
    probe.style.width = 'env(safe-area-inset-right, 0px)';
    var r = probe.getBoundingClientRect().width;
    probe.remove();
    return { left: l, right: r };
  }
  function sideInsets() {
    var v = probeInsetLR(document);
    try {
      var top = topWindow();
      if (top && top.document && top.document.body) {
        var t = probeInsetLR(top.document);
        v = { left: Math.max(v.left, t.left), right: Math.max(v.right, t.right) };
      }
    } catch (e) {}
    return v;
  }

  var lastAppliedH = -1, lastAppliedW = -1;
  // xterm measures scrollBarWidth = viewport.offsetWidth - scrollArea.offsetWidth
  // || 15. On overlay-scrollbar platforms (Android/iOS) the measurement is 0 and
  // the ||15 fallback makes the fit addon reserve 15px of phantom width — a
  // visible gap right of the last column (e.g. at the right end of the status
  // bar). Replace the data property with an accessor that returns the true
  // measurement (0 when the scrollbar overlays, >0 when it takes real space,
  // e.g. the thin scrollbar on desktop). The noop setter absorbs xterm's own
  // re-measure on scroll, which would otherwise throw on the getter-only
  // property in strict mode and reset it to 15.
  function fixScrollBarWidth() {
    try {
      var vp = window.term && window.term._core && window.term._core.viewport;
      if (!vp || !vp._viewportElement || !vp._scrollArea) return;
      var d = Object.getOwnPropertyDescriptor(vp, 'scrollBarWidth');
      if (d && d.get) return; // already installed
      Object.defineProperty(vp, 'scrollBarWidth', {
        configurable: true,
        get: function () {
          var m = vp._viewportElement.offsetWidth - vp._scrollArea.offsetWidth;
          return m > 0 ? m : 0;
        },
        set: function () { /* absorb xterm's internal re-measure */ }
      });
    } catch (e) { /* term not ready yet */ }
  }

  function fitToVisualViewport() {
    var top = topWindow();
    var selfVV = window.visualViewport;
    // base = the ingress iframe's own height (already excludes the HA header);
    // frameElement.top is exactly the header height. Same-origin, so this is
    // readable; fall back to our own viewport when cross-origin.
    var base = Math.round(selfVV ? selfVV.height : window.innerHeight);
    var baseW = window.innerWidth;
    var topOffset = 0, leftOffset = 0;
    try {
      if (window.frameElement) {
        var r = window.frameElement.getBoundingClientRect();
        base = Math.round(r.height);
        topOffset = Math.round(r.top);
        baseW = Math.round(r.width);
        leftOffset = Math.round(r.left);
      }
    } catch (e) { /* cross-origin parent */ }
    // Visible height below the HA header. Stock Chrome resizes the layout
    // viewport when the Android keyboard opens (innerHeight shrinks and the
    // visual viewport follows) -> visible = innerHeight. Brave instead keeps
    // innerHeight and only shrinks visualViewport — and that vv also subtracts
    // Brave's now-hidden bottom bar, so it under-reports the visible height by
    // roughly one bottom bar (measured: leaves a ~100px void above the
    // keyboard). Compensate with half the browser chrome, clamped to the
    // layout viewport.
    var vv = (top && top.visualViewport) || selfVV;
    var layoutH = top ? Math.round(top.innerHeight) : Math.round(window.innerHeight);
    var vvH = vv ? Math.round(vv.height) : layoutH;
    var shrink = Math.max(0, layoutH - vvH);
    var keyboardOpen = shrink > 80;
    var visible = layoutH;
    if (keyboardOpen) {
      var screenH = top ? top.screen.height : screen.height;
      var chrome = Math.max(0, Math.round(screenH - layoutH));
      visible = Math.min(layoutH, vvH + Math.round(chrome / 2));
    }
    var h = Math.min(base, visible - topOffset);
    // when the virtual keyboard is open the gesture bar is gone — don't
    // subtract its inset on top of the already-shrunk viewport
    var inset = keyboardOpen ? 0 : bottomInset();
    h = Math.max(0, h - Math.round(inset));
    // width: with viewport-fit=cover the page can extend under side system
    // bars (landscape gesture bar); subtract the horizontal safe-area insets
    var w = baseW;
    if (document.documentElement.classList.contains('ttyd-patch-mobile') && !keyboardOpen) {
      var lr = sideInsets();
      var tvvW = top && top.visualViewport ? Math.round(top.visualViewport.width) : baseW;
      w = Math.min(baseW, tvvW - leftOffset) - Math.round(lr.left + lr.right);
      w = Math.max(0, w);
    }
    if (h === lastAppliedH && w === lastAppliedW) return; // don't re-dispatch resize on every visualViewport scroll tick
    lastAppliedH = h;
    lastAppliedW = w;
    document.documentElement.style.height = h + 'px';
    document.body.style.height = h + 'px';
    var c = document.getElementById('terminal-container');
    if (c) {
      c.style.height = h + 'px';
      if (document.documentElement.classList.contains('ttyd-patch-mobile')) {
        c.style.width = w + 'px';
        document.documentElement.style.width = w + 'px';
        document.body.style.width = w + 'px';
      }
    }
    if (vv) window.scrollTo(0, vv.offsetTop || 0);
    fixScrollBarWidth();
    window.dispatchEvent(new Event('resize'));
    console.log('ttyd-patch viewport h=' + h + ' base=' + base + ' topOff=' + topOffset +
      ' inset=' + inset + ' kb=' + (keyboardOpen ? 1 : 0));
    setTimeout(logFit, 100);
  }
  var top = topWindow();
  if (top && top.visualViewport) {
    top.visualViewport.addEventListener('resize', fitToVisualViewport);
    top.visualViewport.addEventListener('scroll', fitToVisualViewport);
    top.addEventListener('resize', fitToVisualViewport);
  }
  if (window.visualViewport) {
    window.visualViewport.addEventListener('resize', fitToVisualViewport);
    window.visualViewport.addEventListener('scroll', fitToVisualViewport);
  }
  window.addEventListener('resize', fitToVisualViewport);
  window.addEventListener('orientationchange', fitToVisualViewport);
  // Android: the keyboard animates in over ~300ms after the textarea focuses,
  // and the resize event can fire before the viewport has settled — refit again
  document.addEventListener('focusin', function () {
    setTimeout(fitToVisualViewport, 350);
  });
  // log the fit addon's inputs/outputs so width miscalculations are visible:
  // container width, .xterm width, cols, measured cell width, scrollbar width,
  // and the actual screen/canvas widths
  function logFit() {
    var c = document.getElementById('terminal-container');
    var t = window.term;
    if (!c || !t) return;
    var dims = null, vpSbW = '-', coreSbW = '-', padX = '-';
    try { dims = t._core._renderService.dimensions; } catch (e) {}
    try { coreSbW = t._core.viewport.scrollBarWidth; } catch (e) {}
    var vp = document.querySelector('.xterm-viewport');
    if (vp) vpSbW = vp.offsetWidth - vp.clientWidth;
    if (t.element) {
      var cs = getComputedStyle(t.element);
      padX = cs.paddingLeft + '+' + cs.paddingRight;
    }
    var screen = document.querySelector('.xterm-screen');
    var canvas = document.querySelector('.xterm-screen canvas');
    var frameW = '-', frameL = '-', topW = '-', lr = '-';
    try {
      if (window.frameElement) {
        var fr = window.frameElement.getBoundingClientRect();
        frameW = Math.round(fr.width);
        frameL = Math.round(fr.left);
      }
      if (topWindow()) topW = topWindow().innerWidth;
      var l = sideInsets();
      lr = Math.round(l.left) + '/' + Math.round(l.right);
    } catch (e) {}
    console.log('ttyd-patch fit: containerW=' + Math.round(c.getBoundingClientRect().width) +
      ' innerW=' + window.innerWidth +
      ' frameW=' + frameW + ' frameL=' + frameL + ' topInnerW=' + topW + ' lrInset=' + lr +
      ' xtermW=' + (t.element ? Math.round(t.element.getBoundingClientRect().width) : '-') +
      ' cols=' + t.cols + ' rows=' + t.rows +
      ' cellW=' + (dims ? dims.css.cell.width : '-') +
      ' devCellW=' + (dims ? dims.device.cell.width : '-') +
      ' dpr=' + window.devicePixelRatio +
      ' coreSbW=' + coreSbW + ' vpSbW=' + vpSbW + ' padX=' + padX +
      ' mobileCls=' + (document.documentElement.classList.contains('ttyd-patch-mobile') ? 1 : 0) +
      ' screenW=' + (screen ? Math.round(screen.getBoundingClientRect().width) : '-') +
      ' canvasW=' + (canvas ? canvas.width + 'px(dev)/' + Math.round(canvas.getBoundingClientRect().width) + 'px(css)' : '-') +
      ' => cols*cellW=' + (dims ? Math.round(t.cols * dims.css.cell.width * 10) / 10 : '-'));
  }

  fitToVisualViewport();

  // paint the sub-character remainder (right of the last column / below the
  // last row) with the active terminal theme background instead of xterm's
  // hardcoded #000 viewport background
  var themeTries = 0;
  var themeIv = setInterval(function () {
    var t = window.term;
    if (t && t.options && t.options.theme && t.options.theme.background) {
      document.documentElement.style.setProperty('--ttyd-patch-term-bg', t.options.theme.background);
    }
    if (t && t._core) {
      // refit once the terminal exists so the initial open() fit is redone
      // with the final font metrics
      fixScrollBarWidth();
      window.dispatchEvent(new Event('resize'));
      clearInterval(themeIv);
    } else if (++themeTries > 40) {
      clearInterval(themeIv);
    }
  }, 250);
  setTimeout(logFit, 800);

  // a DPR change (emulator, zoom, moving between monitors) does NOT fire
  // window resize — CSS-pixel innerWidth is unchanged — but xterm re-measures
  // and re-renders at the new DPR. Refit so cols/rows match the new cell size.
  var lastDpr = window.devicePixelRatio;
  function watchDpr() {
    var mq = window.matchMedia('(resolution: ' + lastDpr + 'dppx)');
    mq.addEventListener('change', function () {
      lastDpr = window.devicePixelRatio;
      window.dispatchEvent(new Event('resize'));
      setTimeout(logFit, 100);
      watchDpr();
    });
  }
  watchDpr();

  // one-time boot diagnostic: every candidate for the bottom inset, from both
  // frames, so the real gesture-bar height can be derived on-device
  setTimeout(function () {
    var top = topWindow();
    var vv = window.visualViewport;
    var tvv = top ? top.visualViewport : null;
    console.log('ttyd-patch boot: self innerH=' + window.innerHeight +
      ' vv.h=' + (vv ? Math.round(vv.height) : '-') +
      ' | top innerH=' + (top ? top.innerHeight : '-') +
      ' vv.h=' + (tvv ? Math.round(tvv.height) : '-') +
      ' scale=' + (tvv ? tvv.scale : '-') +
      ' screen.h=' + (top ? top.screen.height : '-') +
      ' availH=' + (top ? top.screen.availHeight : '-') +
      ' | envInset=' + Math.round(bottomInset()) +
      ' topEnvInset=' + (function () {
        try {
          var top = topWindow();
          return top ? Math.round(probeInset(top.document)) : '-';
        } catch (e) { return '-'; }
      })() +
      ' meta=' + (document.querySelector('meta[name="viewport"]') || { content: '?' }).content +
      ' ua=' + navigator.userAgent.slice(0, 70));
  }, 1000);
})();
