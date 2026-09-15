// Métricas para el landing de Inventtia / Carnaval.
// Requiere assets/js/supabase.min.js cargado previamente.
(function () {
  const SUPABASE_URL = 'https://vsieeihstajlrdvpuooh.supabase.co';
  const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzaWVlaWhzdGFqbHJkdnB1b29oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ1MzIyMDYsImV4cCI6MjA3MDEwODIwNn0.ZQmME9zoNTd77WwblxosRv5nnyMTWN8pKkDA6UMKcO4';

  function getSupabase() {
    if (!window.supabase || typeof window.supabase.createClient !== 'function') {
      return null;
    }
    if (!window._ventiqSupabaseClient) {
      window._ventiqSupabaseClient = window.supabase.createClient(
        SUPABASE_URL,
        SUPABASE_ANON_KEY,
      );
    }
    return window._ventiqSupabaseClient;
  }

  function getPlatform() {
    const ua = navigator.userAgent || '';
    if (/Android/i.test(ua)) return 'Android';
    if (
      /iPad|iPhone|iPod/.test(ua) ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1)
    ) {
      return 'iOS';
    }
    return 'Desktop';
  }

  function getSessionId() {
    try {
      let sid = sessionStorage.getItem('ventiq_landing_sid');
      if (!sid) {
        sid =
          (typeof crypto !== 'undefined' && crypto.randomUUID
            ? crypto.randomUUID()
            : Date.now() + '-' + Math.random().toString(36).slice(2));
        sessionStorage.setItem('ventiq_landing_sid', sid);
      }
      return sid;
    } catch (e) {
      return null;
    }
  }

  async function trackLandingEvent(eventType, extra) {
    extra = extra || {};
    const supabase = getSupabase();
    if (!supabase) {
      console.warn('[VentiqTracking] Supabase client not available');
      return;
    }
    try {
      const { error } = await supabase.rpc('fn_track_landing_event', {
        p_event_type: eventType,
        p_code: extra.code || null,
        p_platform: getPlatform(),
        p_user_agent: navigator.userAgent || null,
        p_page_url: window.location.href,
        p_referrer: document.referrer || null,
        p_session_id: getSessionId(),
      });
      if (error) {
        console.error('[VentiqTracking] RPC error:', error);
      }
    } catch (e) {
      console.error('[VentiqTracking] Exception:', e);
    }
  }

  // Exponer globalmente para scripts inline.
  window.VentiqTracking = { track: trackLandingEvent };

  function initAutoClicks() {
    document.querySelectorAll('[data-track-event]').forEach(function (el) {
      const eventType = el.getAttribute('data-track-event');
      const code = el.getAttribute('data-track-code');
      if (!eventType) return;
      el.addEventListener('click', function () {
        trackLandingEvent(eventType, { code: code });
      });
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initAutoClicks);
  } else {
    initAutoClicks();
  }
})();
