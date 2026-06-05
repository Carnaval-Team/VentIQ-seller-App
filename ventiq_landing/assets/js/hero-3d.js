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
    renderer.toneMappingExposure = 1.25;
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
        {
            ringColor: 0x7c3aed,
            texture: 'assets/images/screenshoot.jpg',
            x: -1.55, y:  0.55, z: -0.4, rot: -0.18, scale: 1.0,
        },
        {
            ringColor: 0x4f46e5,
            texture: 'assets/images/images_tutorial_admin/ejecutive_dash_general.jpg',
            x:  0.05, y: -0.25, z:  0.6, rot:  0.05, scale: 1.18,
        },
        {
            ringColor: 0x22d3ee,
            texture: 'assets/images/catalogo.jpg',
            x:  1.65, y:  0.45, z: -0.6, rot:  0.22, scale: 0.95,
        },
    ];

    // Geometries: one frame (extruded rounded plane) + one flat screen (slightly smaller, sits on top)
    const W = 1.7, H = 2.4;
    const frameGeom = roundedPlane(THREE, W, H, 0.24, 12);
    const screenGeom = roundedPlaneFlat(THREE, W - 0.12, H - 0.12, 0.20, 14);

    const texLoader = new THREE.TextureLoader();
    texLoader.crossOrigin = 'anonymous';

    slabConfigs.forEach((cfg, i) => {
        const ringColor = new THREE.Color(cfg.ringColor);

        // Frame: dark iridescent bezel — looks like the chassis of a device
        const frameMat = new THREE.MeshPhysicalMaterial({
            color: new THREE.Color(0x0a0c16),
            metalness: 0.9,
            roughness: 0.28,
            emissive: ringColor.clone().multiplyScalar(0.18),
            emissiveIntensity: 0.6,
            iridescence: 1.0,
            iridescenceIOR: 1.4,
            iridescenceThicknessRange: [240, 820],
            clearcoat: 1.0,
            clearcoatRoughness: 0.08,
            envMapIntensity: 1.4,
            side: THREE.DoubleSide,
        });

        const frame = new THREE.Mesh(frameGeom, frameMat);

        // Screen: app screenshot textured plane, sits a hair in front of the frame
        const tex = texLoader.load(
            cfg.texture,
            (t) => {
                t.colorSpace = THREE.SRGBColorSpace;
                t.anisotropy = renderer.capabilities.getMaxAnisotropy();
                t.needsUpdate = true;
            },
            undefined,
            (err) => console.warn('[hero-3d] texture failed', cfg.texture, err)
        );
        tex.colorSpace = THREE.SRGBColorSpace;

        const screenMat = new THREE.MeshPhysicalMaterial({
            map: tex,
            metalness: 0.0,
            roughness: 0.42,
            clearcoat: 0.8,
            clearcoatRoughness: 0.18,
            envMapIntensity: 0.55,
            side: THREE.FrontSide,
        });

        const screen = new THREE.Mesh(screenGeom, screenMat);
        // Push the screen forward along the frame's depth so it appears mounted on top
        screen.position.z = 0.105;

        // Group both as the slab unit
        const slab = new THREE.Group();
        slab.add(frame);
        slab.add(screen);
        slab.position.set(cfg.x, cfg.y, cfg.z);
        slab.rotation.z = cfg.rot;
        slab.scale.setScalar(cfg.scale);
        slab.userData = { baseY: cfg.y, baseRot: cfg.rot, phase: i * 1.7 };

        group.add(slab);
        slabs.push(slab);
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
        frameGeom.dispose();
        screenGeom.dispose();
        slabs.forEach((slab) => {
            slab.traverse((obj) => {
                if (obj.isMesh) {
                    obj.material?.map?.dispose?.();
                    obj.material?.dispose?.();
                }
            });
        });
        env.dispose();
        pmrem.dispose();
    }, { once: true });
}

/* ---------- helpers ---------- */

function roundedRectShape(THREE, w, h, r) {
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
    return shape;
}

function roundedPlane(THREE, w, h, r, seg) {
    // Build a rounded rectangle ShapeGeometry then extrude slightly for depth (used as device frame)
    const shape = roundedRectShape(THREE, w, h, r);
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

function roundedPlaneFlat(THREE, w, h, r, seg) {
    // Flat rounded rect with proper UVs so a screenshot maps cleanly to the surface.
    const shape = roundedRectShape(THREE, w, h, r);
    const geom = new THREE.ShapeGeometry(shape, seg);

    // Re-build UVs: ShapeGeometry inherits the shape coordinates as UVs (can go negative).
    // Remap to [0,1] across the bounding box and flip Y for image textures.
    geom.computeBoundingBox();
    const min = geom.boundingBox.min;
    const max = geom.boundingBox.max;
    const sx = 1 / (max.x - min.x);
    const sy = 1 / (max.y - min.y);
    const pos = geom.attributes.position;
    const uv = new Float32Array(pos.count * 2);
    for (let i = 0; i < pos.count; i++) {
        const u = (pos.getX(i) - min.x) * sx;
        const v = 1 - (pos.getY(i) - min.y) * sy; // flip Y so top of image = top of plane
        uv[i * 2] = u;
        uv[i * 2 + 1] = v;
    }
    geom.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
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

    // sparkle highlights — brighter + more numerous so iridescence has crisp reflections to bend
    ctx.globalCompositeOperation = 'lighter';
    for (let i = 0; i < 140; i++) {
        const cx = Math.random() * 512;
        const cy = Math.random() * 256;
        const r = Math.random() * 8 + 2;
        const g = ctx.createRadialGradient(cx, cy, 0, cx, cy, r);
        g.addColorStop(0, 'rgba(255,255,255,0.95)');
        g.addColorStop(0.4, 'rgba(255,255,255,0.5)');
        g.addColorStop(1, 'rgba(255,255,255,0)');
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(cx, cy, r, 0, Math.PI * 2);
        ctx.fill();
    }

    // a couple of large bright zones — strong light sources for clearcoat highlights
    [[120, 80, 90], [380, 60, 110], [260, 200, 80]].forEach(([x, y, r]) => {
        const g = ctx.createRadialGradient(x, y, 0, x, y, r);
        g.addColorStop(0, 'rgba(255,255,255,0.45)');
        g.addColorStop(1, 'rgba(255,255,255,0)');
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(x, y, r, 0, Math.PI * 2);
        ctx.fill();
    });

    const tex = new THREE.CanvasTexture(canvas);
    tex.mapping = THREE.EquirectangularReflectionMapping;
    tex.colorSpace = THREE.SRGBColorSpace;
    const envRT = pmrem.fromEquirectangular(tex);
    tex.dispose();
    return envRT.texture;
}
