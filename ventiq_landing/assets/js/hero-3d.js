/* =========================================================
   INVENTTIA · Hero 3D scene
   Three.js iridescent slabs · lazy-loaded, reduced-motion safe
   ========================================================= */

const STAGE = document.querySelector('[data-hero-stage]');
const FALLBACK = document.querySelector('[data-hero-fallback]');

// Reduced motion → keep the static fallback, do not load Three.js
const REDUCE = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
// Touch / small screens → keep fallback (perf + meaningful experience)
const IS_SMALL = window.matchMedia('(max-width: 720px)').matches;

if (!STAGE || REDUCE || IS_SMALL) {
    // Show fallback gracefully and bail.
    if (FALLBACK) FALLBACK.style.display = 'grid';
} else {
    // Use IntersectionObserver to defer loading until visible
    const io = new IntersectionObserver((entries, obs) => {
        for (const entry of entries) {
            if (entry.isIntersecting) {
                obs.disconnect();
                bootScene().catch((err) => {
                    console.warn('[hero-3d] scene boot failed, keeping fallback', err);
                    if (FALLBACK) FALLBACK.style.display = 'grid';
                });
                break;
            }
        }
    }, { rootMargin: '200px' });
    io.observe(STAGE);
}

async function bootScene() {
    // Dynamic import via CDN ESM build
    const THREE = await import('https://cdn.jsdelivr.net/npm/three@0.160.0/build/three.module.js');

    const width  = STAGE.clientWidth;
    const height = STAGE.clientHeight;

    // ---------- Renderer ----------
    const renderer = new THREE.WebGLRenderer({
        antialias: true,
        alpha: true,
        powerPreference: 'high-performance',
    });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    renderer.setSize(width, height);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.05;
    STAGE.appendChild(renderer.domElement);

    // ---------- Scene ----------
    const scene = new THREE.Scene();
    scene.background = null;

    // ---------- Camera ----------
    const camera = new THREE.PerspectiveCamera(38, width / height, 0.1, 100);
    camera.position.set(0, 0, 7);

    // ---------- Environment (procedural so we ship no HDR) ----------
    const pmrem = new THREE.PMREMGenerator(renderer);
    const env = makeGradientEnv(THREE, pmrem);
    scene.environment = env;

    // ---------- Lights ----------
    const key = new THREE.DirectionalLight(0xffffff, 1.2);
    key.position.set(4, 5, 4);
    scene.add(key);

    const rim = new THREE.DirectionalLight(0x7c3aed, 1.4);
    rim.position.set(-4, -2, -3);
    scene.add(rim);

    const fill = new THREE.DirectionalLight(0x22d3ee, 0.8);
    fill.position.set(-3, 4, 2);
    scene.add(fill);

    scene.add(new THREE.AmbientLight(0xb7becE, 0.18));

    // ---------- Group ----------
    const group = new THREE.Group();
    scene.add(group);

    // ---------- Slabs (3 = one per app: Vendedor / Admin / Catálogo) ----------
    const slabs = [];
    const slabConfigs = [
        { color: 0x7c3aed, x: -1.45, y:  0.55, z: -0.4, rot: -0.18, scale: 1.0 },
        { color: 0x4f46e5, x:  0.05, y: -0.25, z:  0.6, rot:  0.05, scale: 1.18 },
        { color: 0x22d3ee, x:  1.55, y:  0.45, z: -0.6, rot:  0.22, scale: 0.95 },
    ];

    const slabGeom = roundedPlane(THREE, 1.7, 2.4, 0.28, 12);

    slabConfigs.forEach((cfg, i) => {
        const mat = new THREE.MeshPhysicalMaterial({
            color: new THREE.Color(cfg.color),
            metalness: 0.1,
            roughness: 0.12,
            transmission: 0.92,
            thickness: 0.6,
            ior: 1.45,
            attenuationColor: new THREE.Color(cfg.color),
            attenuationDistance: 2.4,
            iridescence: 0.85,
            iridescenceIOR: 1.35,
            iridescenceThicknessRange: [180, 720],
            clearcoat: 1.0,
            clearcoatRoughness: 0.08,
            envMapIntensity: 1.4,
            side: THREE.DoubleSide,
        });

        const mesh = new THREE.Mesh(slabGeom, mat);
        mesh.position.set(cfg.x, cfg.y, cfg.z);
        mesh.rotation.z = cfg.rot;
        mesh.scale.setScalar(cfg.scale);
        mesh.userData = { baseY: cfg.y, baseRot: cfg.rot, phase: i * 1.7 };
        group.add(mesh);
        slabs.push(mesh);
    });

    // ---------- Floating particles (soft accents) ----------
    const dustCount = 60;
    const dustGeom = new THREE.BufferGeometry();
    const dustPos = new Float32Array(dustCount * 3);
    for (let i = 0; i < dustCount; i++) {
        dustPos[i*3]   = (Math.random() - 0.5) * 8;
        dustPos[i*3+1] = (Math.random() - 0.5) * 6;
        dustPos[i*3+2] = (Math.random() - 0.5) * 4 - 1;
    }
    dustGeom.setAttribute('position', new THREE.BufferAttribute(dustPos, 3));
    const dust = new THREE.Points(dustGeom, new THREE.PointsMaterial({
        color: 0xffffff,
        size: 0.025,
        transparent: true,
        opacity: 0.55,
        depthWrite: false,
    }));
    scene.add(dust);

    // ---------- Pointer parallax ----------
    const pointer = { x: 0, y: 0, tx: 0, ty: 0 };
    const onPointerMove = (e) => {
        const rect = STAGE.getBoundingClientRect();
        pointer.tx = ((e.clientX - rect.left) / rect.width  - 0.5) * 2;
        pointer.ty = ((e.clientY - rect.top)  / rect.height - 0.5) * 2;
    };
    STAGE.addEventListener('pointermove', onPointerMove);
    STAGE.addEventListener('pointerleave', () => { pointer.tx = 0; pointer.ty = 0; });

    // ---------- Resize ----------
    const onResize = () => {
        const w = STAGE.clientWidth;
        const h = STAGE.clientHeight;
        renderer.setSize(w, h);
        camera.aspect = w / h;
        camera.updateProjectionMatrix();
    };
    const ro = new ResizeObserver(onResize);
    ro.observe(STAGE);

    // ---------- Pause when offscreen ----------
    let isVisible = true;
    const visIO = new IntersectionObserver((entries) => {
        for (const e of entries) isVisible = e.isIntersecting;
    });
    visIO.observe(STAGE);

    // ---------- Loop ----------
    const clock = new THREE.Clock();
    function frame() {
        if (!isVisible) {
            requestAnimationFrame(frame);
            return;
        }
        const t = clock.getElapsedTime();

        // smooth pointer
        pointer.x += (pointer.tx - pointer.x) * 0.06;
        pointer.y += (pointer.ty - pointer.y) * 0.06;

        // group parallax tilt
        group.rotation.y = pointer.x * 0.32;
        group.rotation.x = -pointer.y * 0.18;

        slabs.forEach((slab, i) => {
            // float
            slab.position.y = slab.userData.baseY + Math.sin(t * 0.7 + slab.userData.phase) * 0.12;
            // gentle self-rotation
            slab.rotation.y = Math.sin(t * 0.35 + slab.userData.phase) * 0.28;
            slab.rotation.z = slab.userData.baseRot + Math.sin(t * 0.4 + i) * 0.04;
        });

        // dust drift
        dust.rotation.y = t * 0.04;
        dust.rotation.x = Math.sin(t * 0.1) * 0.05;

        renderer.render(scene, camera);
        requestAnimationFrame(frame);
    }
    frame();

    // Hide fallback once first frame is in
    if (FALLBACK) FALLBACK.style.opacity = '0';
    setTimeout(() => { if (FALLBACK) FALLBACK.style.display = 'none'; }, 500);

    // Cleanup on full unload
    window.addEventListener('beforeunload', () => {
        ro.disconnect();
        visIO.disconnect();
        renderer.dispose();
        slabGeom.dispose();
        slabs.forEach(s => s.material.dispose());
        env.dispose();
        pmrem.dispose();
    }, { once: true });
}

/* ---------- helpers ---------- */

function roundedPlane(THREE, w, h, r, seg) {
    // Build a rounded rectangle ShapeGeometry then extrude slightly for depth
    const shape = new THREE.Shape();
    const x = -w / 2;
    const y = -h / 2;
    shape.moveTo(x + r, y);
    shape.lineTo(x + w - r, y);
    shape.quadraticCurveTo(x + w, y, x + w, y + r);
    shape.lineTo(x + w, y + h - r);
    shape.quadraticCurveTo(x + w, y + h, x + w - r, y + h);
    shape.lineTo(x + r, y + h);
    shape.quadraticCurveTo(x, y + h, x, y + h - r);
    shape.lineTo(x, y + r);
    shape.quadraticCurveTo(x, y, x + r, y);

    const geom = new THREE.ExtrudeGeometry(shape, {
        depth: 0.18,
        bevelEnabled: true,
        bevelThickness: 0.04,
        bevelSize: 0.04,
        bevelSegments: 6,
        curveSegments: seg,
    });
    geom.center();
    return geom;
}

function makeGradientEnv(THREE, pmrem) {
    // Procedural sky-style env: 3 colored gradient as equirect texture
    const canvas = document.createElement('canvas');
    canvas.width = 512;
    canvas.height = 256;
    const ctx = canvas.getContext('2d');
    const grad = ctx.createLinearGradient(0, 0, 0, 256);
    grad.addColorStop(0.0, '#1E1B4B');
    grad.addColorStop(0.35, '#7C3AED');
    grad.addColorStop(0.65, '#4F46E5');
    grad.addColorStop(1.0, '#22D3EE');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, 512, 256);

    // sparkle highlights
    ctx.globalCompositeOperation = 'lighter';
    for (let i = 0; i < 60; i++) {
        const cx = Math.random() * 512;
        const cy = Math.random() * 256;
        const r = Math.random() * 6 + 2;
        const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
        g.addColorStop(0, 'rgba(255,255,255,0.6)');
        g.addColorStop(1, 'rgba(255,255,255,0)');
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, Math.PI * 2);
        ctx.fill();
    }

    const tex = new THREE.CanvasTexture(canvas);
    tex.mapping = THREE.EquirectangularReflectionMapping;
    tex.colorSpace = THREE.SRGBColorSpace;
    const envRT = pmrem.fromEquirectangular(tex);
    tex.dispose();
    return envRT.texture;
}
