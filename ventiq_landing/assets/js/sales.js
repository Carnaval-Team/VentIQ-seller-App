/* =========================================================
   INVENTTIA · Servicios + Contacto
   FAQ acordeón · formulario que compone el mensaje
   No hay backend: el envío abre WhatsApp o el cliente de correo
   con el mensaje ya redactado.
   (El menú móvil lo maneja premium-v2.js, común a todas las páginas v2.)
   ========================================================= */

(function () {
    'use strict';

    // Datos de contacto en un solo lugar: si cambian, se cambian aquí.
    const WHATSAPP = '5363464544';
    const EMAIL = 'soporteinventtia@gmail.com';

    document.addEventListener('DOMContentLoaded', function () {
        initFaq();
        initForm();
    });

    /* ---------- 1. FAQ acordeón ---------- */
    function initFaq() {
        const items = document.querySelectorAll('.v2-faq-item');
        if (!items.length) return;

        items.forEach((item) => {
            const btn = item.querySelector('.v2-faq-q');
            const answer = item.querySelector('.v2-faq-a');
            if (!btn || !answer) return;

            btn.addEventListener('click', () => {
                const willOpen = !item.classList.contains('is-open');

                // Acordeón de uno en uno: cerrar el resto.
                items.forEach((other) => {
                    if (other === item) return;
                    other.classList.remove('is-open');
                    const otherBtn = other.querySelector('.v2-faq-q');
                    const otherAns = other.querySelector('.v2-faq-a');
                    if (otherBtn) otherBtn.setAttribute('aria-expanded', 'false');
                    if (otherAns) otherAns.setAttribute('aria-hidden', 'true');
                });

                item.classList.toggle('is-open', willOpen);
                btn.setAttribute('aria-expanded', String(willOpen));
                answer.setAttribute('aria-hidden', String(!willOpen));
            });
        });
    }

    /* ---------- 2. Formulario ---------- */
    function initForm() {
        const form = document.querySelector('[data-contact-form]');
        if (!form) return;

        // Marca visual del canal elegido (fallback donde :has() no existe).
        const channelOpts = form.querySelectorAll('.v2-channel-opt');
        const syncChannel = () => {
            channelOpts.forEach((opt) => {
                const radio = opt.querySelector('input[type="radio"]');
                opt.classList.toggle('is-checked', !!radio && radio.checked);
            });
        };
        channelOpts.forEach((opt) => {
            const radio = opt.querySelector('input[type="radio"]');
            if (radio) radio.addEventListener('change', syncChannel);
        });
        syncChannel();

        // Limpiar el error en cuanto la persona corrige el campo.
        form.querySelectorAll('input, select, textarea').forEach((field) => {
            field.addEventListener('input', () => clearError(field));
            field.addEventListener('change', () => clearError(field));
        });

        // Pre-llenado desde la URL: sales.html enlaza aquí con ?asunto=desarrollo
        prefillFromQuery(form);

        form.addEventListener('submit', (e) => {
            e.preventDefault();
            if (!validate(form)) return;
            send(form);
        });
    }

    function prefillFromQuery(form) {
        const params = new URLSearchParams(window.location.search);
        const asunto = params.get('asunto');
        if (!asunto) return;

        const select = form.querySelector('[name="asunto"]');
        if (!select) return;

        // Solo aceptamos valores que existan en el select.
        const match = Array.from(select.options).some((o) => o.value === asunto);
        if (match) select.value = asunto;
    }

    function validate(form) {
        let ok = true;
        let firstBad = null;

        form.querySelectorAll('[required]').forEach((field) => {
            const value = (field.value || '').trim();

            if (!value) {
                showError(field, 'Este campo es obligatorio');
                ok = false;
                if (!firstBad) firstBad = field;
                return;
            }

            if (field.type === 'email' && !/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value)) {
                showError(field, 'Revisa el formato del correo');
                ok = false;
                if (!firstBad) firstBad = field;
                return;
            }

            clearError(field);
        });

        if (firstBad) firstBad.focus();
        return ok;
    }

    function showError(field, message) {
        const wrap = field.closest('.v2-field');
        if (!wrap) return;
        wrap.classList.add('has-error');

        let node = wrap.querySelector('.v2-field-error');
        if (!node) {
            node = document.createElement('div');
            node.className = 'v2-field-error';
            wrap.appendChild(node);
        }
        node.textContent = message;
    }

    function clearError(field) {
        const wrap = field.closest('.v2-field');
        if (!wrap) return;
        wrap.classList.remove('has-error');
        const node = wrap.querySelector('.v2-field-error');
        if (node) node.remove();
    }

    function send(form) {
        const data = new FormData(form);
        const get = (k) => (data.get(k) || '').toString().trim();

        const nombre = get('nombre');
        const email = get('email');
        const telefono = get('telefono');
        const organizacion = get('organizacion');
        const asuntoValue = get('asunto');
        const mensaje = get('mensaje');
        const canal = get('canal') || 'whatsapp';

        // Etiqueta legible del asunto, no el value interno.
        const select = form.querySelector('[name="asunto"]');
        let asuntoLabel = asuntoValue;
        if (select && select.selectedIndex >= 0) {
            asuntoLabel = select.options[select.selectedIndex].text;
        }

        const lines = [
            'Hola Inventtia, escribo desde el sitio web.',
            '',
            'Asunto: ' + asuntoLabel,
            'Nombre: ' + nombre,
        ];
        if (organizacion) lines.push('Organización: ' + organizacion);
        lines.push('Correo: ' + email);
        if (telefono) lines.push('Teléfono: ' + telefono);
        lines.push('', 'Mensaje:', mensaje);

        const body = lines.join('\n');
        const subject = 'Inventtia · ' + asuntoLabel + ' · ' + nombre;

        if (canal === 'email') {
            window.location.href =
                'mailto:' + EMAIL +
                '?subject=' + encodeURIComponent(subject) +
                '&body=' + encodeURIComponent(body);
            toast('Abriendo tu correo con el mensaje listo para enviar.');
        } else {
            window.open('https://wa.me/' + WHATSAPP + '?text=' + encodeURIComponent(body), '_blank', 'noopener');
            toast('Abriendo WhatsApp con el mensaje listo para enviar.');
        }
    }

    /* ---------- 3. Aviso flotante ---------- */
    let toastTimer = null;

    function toast(message) {
        let node = document.querySelector('.v2-toast');
        if (!node) {
            node = document.createElement('div');
            node.className = 'v2-toast';
            node.setAttribute('role', 'status');
            node.innerHTML = '<i class="fas fa-circle-check" aria-hidden="true"></i><span></span>';
            document.body.appendChild(node);
        }
        node.querySelector('span').textContent = message;

        // Un frame de margen para que la transición arranque desde el estado oculto.
        requestAnimationFrame(() => node.classList.add('is-in'));

        clearTimeout(toastTimer);
        toastTimer = setTimeout(() => node.classList.remove('is-in'), 5200);
    }
})();
