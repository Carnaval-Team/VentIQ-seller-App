// Main JavaScript for VentIQ Landing Page

document.addEventListener('DOMContentLoaded', function() {
    // Initialize all components
    initNavigation();
    initScrollEffects();
    initAnimations();
    initDownloadButtons();
});

// Navigation functionality
function initNavigation() {
    const navbar = document.querySelector('.navbar');
    const hamburger = document.querySelector('.hamburger');
    const navMenu = document.querySelector('.nav-menu');
    
    // Scroll effect for navbar
    window.addEventListener('scroll', function() {
        if (window.scrollY > 50) {
            navbar.classList.add('scrolled');
        } else {
            navbar.classList.remove('scrolled');
        }
    });
    
    // Mobile menu toggle
    if (hamburger && navMenu) {
        hamburger.addEventListener('click', function() {
            hamburger.classList.toggle('active');
            navMenu.classList.toggle('active');
        });
        
        // Close mobile menu when clicking on a link
        const navLinks = document.querySelectorAll('.nav-link');
        navLinks.forEach(link => {
            link.addEventListener('click', function() {
                hamburger.classList.remove('active');
                navMenu.classList.remove('active');
            });
        });
        
        // Close mobile menu when clicking outside
        document.addEventListener('click', function(e) {
            if (!hamburger.contains(e.target) && !navMenu.contains(e.target)) {
                hamburger.classList.remove('active');
                navMenu.classList.remove('active');
            }
        });
    }
}

// Scroll effects and animations
function initScrollEffects() {
    // Smooth scrolling for anchor links
    const anchorLinks = document.querySelectorAll('a[href^="#"]');
    anchorLinks.forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            const targetId = this.getAttribute('href');
            const targetElement = document.querySelector(targetId);
            
            if (targetElement) {
                const offsetTop = targetElement.offsetTop - 70; // Account for fixed navbar
                window.scrollTo({
                    top: offsetTop,
                    behavior: 'smooth'
                });
            }
        });
    });
    
    // Intersection Observer for fade-in animations
    const observerOptions = {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
    };
    
    const observer = new IntersectionObserver(function(entries) {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('animate-in');
            }
        });
    }, observerOptions);
    
    // Observe elements for animation
    const animateElements = document.querySelectorAll('.benefit-card, .app-card, .tutorial-card, .feature-item');
    animateElements.forEach(el => {
        observer.observe(el);
    });
}

// Initialize animations
function initAnimations() {
    // Add CSS for fade-in animations
    const style = document.createElement('style');
    style.textContent = `
        .benefit-card, .app-card, .tutorial-card, .feature-item {
            opacity: 0;
            transform: translateY(30px);
            transition: opacity 0.6s ease-out, transform 0.6s ease-out;
        }
        
        .benefit-card.animate-in, .app-card.animate-in, .tutorial-card.animate-in, .feature-item.animate-in {
            opacity: 1;
            transform: translateY(0);
        }
        
        .floating-card {
            animation: float 6s ease-in-out infinite;
        }
        
        @keyframes float {
            0%, 100% { transform: translateY(0px); }
            50% { transform: translateY(-20px); }
        }
        
        .hero-stats .stat {
            animation: countUp 2s ease-out;
        }
        
        @keyframes countUp {
            from { transform: scale(0.8); opacity: 0; }
            to { transform: scale(1); opacity: 1; }
        }
    `;
    document.head.appendChild(style);
    
    // Animate hero stats on load
    setTimeout(() => {
        const stats = document.querySelectorAll('.stat');
        stats.forEach((stat, index) => {
            setTimeout(() => {
                stat.style.animation = 'countUp 0.8s ease-out forwards';
            }, index * 200);
        });
    }, 1000);
}

// Download buttons functionality
function initDownloadButtons() {
    const downloadButtons = document.querySelectorAll('.download-btn, .download-app-btn, .download-link');
    
    downloadButtons.forEach(button => {
        button.addEventListener('click', function(e) {
            e.preventDefault();
            
            // Determine which app based on button class or content
            const isSellerApp = this.classList.contains('seller-app') || 
                              this.textContent.toLowerCase().includes('seller') ||
                              this.textContent.toLowerCase().includes('móvil');
            
            if (isSellerApp) {
                showDownloadModal('VentIQ Seller App', 'seller');
            } else {
                showDownloadModal('VentIQ Admin Web', 'admin');
            }
        });
    });
}

// Show download modal
function showDownloadModal(appName, appType) {
    // Create modal if it doesn't exist
    let modal = document.getElementById('downloadModal');
    if (!modal) {
        modal = createDownloadModal();
        document.body.appendChild(modal);
    }
    
    // Update modal content
    const title = modal.querySelector('.modal-title');
    const content = modal.querySelector('.modal-body');
    
    title.textContent = `Descargar ${appName}`;
    
    if (appType === 'seller') {
        content.innerHTML = `
            <div class="download-options">
                <div class="download-option">
                    <i class="fab fa-android"></i>
                    <div>
                        <h4>Android</h4>
                        <p>Aplicación nativa Flutter</p>
                        <button class="btn btn-primary" onclick="downloadApp('android-seller')">
                            <i class="fas fa-download"></i>
                            Descargar APK
                        </button>
                    </div>
                </div>
                <div class="download-option">
                    <i class="fab fa-apple"></i>
                    <div>
                        <h4>iOS</h4>
                        <p>Disponible en App Store</p>
                        <button class="btn btn-secondary" onclick="downloadApp('ios-seller')">
                            <i class="fas fa-external-link-alt"></i>
                            Ir a App Store
                        </button>
                    </div>
                </div>
                <div class="download-option">
                    <i class="fas fa-globe"></i>
                    <div>
                        <h4>Web</h4>
                        <p>Acceso directo desde navegador</p>
                        <button class="btn btn-primary" onclick="openWebApp('seller')">
                            <i class="fas fa-external-link-alt"></i>
                            Abrir VentIQ Seller Web
                        </button>
                    </div>
                </div>
            </div>
        `;
    } else {
        content.innerHTML = `
            <div class="download-options">
                <div class="download-option">
                    <i class="fab fa-android"></i>
                    <div>
                        <h4>Android</h4>
                        <p>Aplicación nativa Flutter</p>
                        <button class="btn btn-primary" onclick="downloadApp('android-admin')">
                            <i class="fas fa-download"></i>
                            Descargar APK
                        </button>
                    </div>
                </div>
                <div class="download-option">
                    <i class="fab fa-apple"></i>
                    <div>
                        <h4>iOS</h4>
                        <p>Disponible en App Store</p>
                        <button class="btn btn-secondary" onclick="downloadApp('ios-admin')">
                            <i class="fas fa-external-link-alt"></i>
                            Ir a App Store
                        </button>
                    </div>
                </div>
                <div class="download-option">
                    <i class="fas fa-globe"></i>
                    <div>
                        <h4>Web</h4>
                        <p>Acceso directo desde navegador</p>
                        <button class="btn btn-primary" onclick="openWebApp('admin')">
                            <i class="fas fa-external-link-alt"></i>
                            Abrir VentIQ Admin Web
                        </button>
                    </div>
                </div>
            </div>
        `;
    }
    
    // Show modal
    modal.classList.add('active');
}

// Create download modal
function createDownloadModal() {
    const modal = document.createElement('div');
    modal.id = 'downloadModal';
    modal.className = 'download-modal';
    modal.innerHTML = `
        <div class="modal-overlay"></div>
        <div class="modal-content">
            <div class="modal-header">
                <h3 class="modal-title">Descargar Aplicación</h3>
                <button class="close-btn" onclick="closeDownloadModal()">
                    <i class="fas fa-times"></i>
                </button>
            </div>
            <div class="modal-body">
                <!-- Content will be inserted dynamically -->
            </div>
        </div>
    `;
    
    // Add modal styles
    const modalStyles = document.createElement('style');
    modalStyles.textContent = `
        .download-modal {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            z-index: 2000;
            display: none;
            align-items: center;
            justify-content: center;
            padding: var(--spacing-lg);
        }
        
        .download-modal.active {
            display: flex;
            animation: modalFadeIn 0.3s ease-out;
        }
        
        .download-modal .modal-overlay {
            position: absolute;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 0, 0, 0.8);
            backdrop-filter: blur(5px);
        }
        
        .download-modal .modal-content {
            background: var(--surface);
            border-radius: var(--radius-xl);
            width: 100%;
            max-width: 500px;
            position: relative;
            z-index: 1;
            animation: modalSlideIn 0.3s ease-out;
        }
        
        .download-modal .modal-header {
            padding: var(--spacing-xl);
            border-bottom: 1px solid var(--border);
            display: flex;
            align-items: center;
            justify-content: space-between;
            background: var(--gradient-primary);
            color: white;
            border-radius: var(--radius-xl) var(--radius-xl) 0 0;
        }
        
        .download-modal .modal-title {
            font-size: 1.25rem;
            font-weight: 600;
            margin: 0;
        }
        
        .download-modal .close-btn {
            background: none;
            border: none;
            color: white;
            font-size: 1.25rem;
            cursor: pointer;
            padding: var(--spacing-sm);
            border-radius: var(--radius-md);
            transition: var(--transition-fast);
        }
        
        .download-modal .close-btn:hover {
            background: rgba(255, 255, 255, 0.1);
        }
        
        .download-modal .modal-body {
            padding: var(--spacing-xl);
        }
        
        .download-options {
            display: flex;
            flex-direction: column;
            gap: var(--spacing-lg);
        }
        
        .download-option {
            display: flex;
            align-items: center;
            gap: var(--spacing-lg);
            padding: var(--spacing-lg);
            border: 2px solid var(--border);
            border-radius: var(--radius-lg);
            transition: var(--transition-fast);
        }
        
        .download-option:hover {
            border-color: var(--primary);
            background: rgba(74, 144, 226, 0.05);
        }
        
        .download-option.single {
            text-align: center;
            flex-direction: column;
        }
        
        .download-option i {
            font-size: 2.5rem;
            color: var(--primary);
            flex-shrink: 0;
        }
        
        .download-option h4 {
            font-size: 1.125rem;
            font-weight: 600;
            margin-bottom: var(--spacing-xs);
            color: var(--text-primary);
        }
        
        .download-option p {
            color: var(--text-secondary);
            margin-bottom: var(--spacing-md);
            font-size: 0.875rem;
        }
        
        @keyframes modalFadeIn {
            from { opacity: 0; }
            to { opacity: 1; }
        }
        
        @keyframes modalSlideIn {
            from {
                opacity: 0;
                transform: translateY(-50px) scale(0.95);
            }
            to {
                opacity: 1;
                transform: translateY(0) scale(1);
            }
        }
        
        @media (max-width: 480px) {
            .download-option {
                flex-direction: column;
                text-align: center;
                gap: var(--spacing-md);
            }
        }
    `;
    document.head.appendChild(modalStyles);
    
    // Close modal when clicking overlay
    modal.querySelector('.modal-overlay').addEventListener('click', closeDownloadModal);
    
    return modal;
}

// Close download modal
function closeDownloadModal() {
    const modal = document.getElementById('downloadModal');
    if (modal) {
        modal.classList.remove('active');
    }
}

// Download app functions
function downloadApp(platform) {
    if (platform === 'android-seller') {
        showNotification('Descarga iniciada', 'La descarga del APK de VentIQ Seller comenzará en breve.', 'success');
        // window.open('path/to/ventiq-seller.apk', '_blank');
    } else if (platform === 'ios-seller') {
        showNotification('Redirigiendo...', 'Te redirigimos a la App Store para VentIQ Seller.', 'info');
        // window.open('https://apps.apple.com/app/ventiq-seller', '_blank');
    } else if (platform === 'android-admin') {
        showNotification('Descarga iniciada', 'La descarga del APK de VentIQ Admin comenzará en breve.', 'success');
        // window.open('path/to/ventiq-admin.apk', '_blank');
    } else if (platform === 'ios-admin') {
        showNotification('Redirigiendo...', 'Te redirigimos a la App Store para VentIQ Admin.', 'info');
        // window.open('https://apps.apple.com/app/ventiq-admin', '_blank');
    }
    closeDownloadModal();
}

function openWebApp(appType) {
    if (appType === 'seller') {
        showNotification('Abriendo aplicación...', 'VentIQ Seller Web se abrirá en una nueva pestaña.', 'info');
        // window.open('https://seller.ventiq.com', '_blank');
    } else {
        showNotification('Abriendo aplicación...', 'VentIQ Admin Web se abrirá en una nueva pestaña.', 'info');
        // window.open('https://admin.ventiq.com', '_blank');
    }
    closeDownloadModal();
}

// Show notification
function showNotification(title, message, type = 'info') {
    // Create notification if it doesn't exist
    let notification = document.getElementById('notification');
    if (!notification) {
        notification = createNotification();
        document.body.appendChild(notification);
    }
    
    // Update notification content
    const icon = notification.querySelector('.notification-icon');
    const titleEl = notification.querySelector('.notification-title');
    const messageEl = notification.querySelector('.notification-message');
    
    // Set icon based on type
    const icons = {
        success: 'fas fa-check-circle',
        error: 'fas fa-exclamation-circle',
        warning: 'fas fa-exclamation-triangle',
        info: 'fas fa-info-circle'
    };
    
    icon.className = `notification-icon ${icons[type] || icons.info}`;
    titleEl.textContent = title;
    messageEl.textContent = message;
    
    // Set notification type class
    notification.className = `notification ${type}`;
    
    // Show notification
    notification.classList.add('active');
    
    // Auto hide after 4 seconds
    setTimeout(() => {
        notification.classList.remove('active');
    }, 4000);
}

// Create notification element
function createNotification() {
    const notification = document.createElement('div');
    notification.id = 'notification';
    notification.className = 'notification';
    notification.innerHTML = `
        <i class="notification-icon"></i>
        <div class="notification-content">
            <div class="notification-title"></div>
            <div class="notification-message"></div>
        </div>
        <button class="notification-close" onclick="closeNotification()">
            <i class="fas fa-times"></i>
        </button>
    `;
    
    // Add notification styles
    const notificationStyles = document.createElement('style');
    notificationStyles.textContent = `
        .notification {
            position: fixed;
            top: 20px;
            right: 20px;
            background: var(--surface);
            border-radius: var(--radius-lg);
            padding: var(--spacing-lg);
            box-shadow: var(--shadow-xl);
            border-left: 4px solid var(--primary);
            display: flex;
            align-items: center;
            gap: var(--spacing-md);
            max-width: 400px;
            z-index: 3000;
            transform: translateX(100%);
            transition: var(--transition-normal);
        }
        
        .notification.active {
            transform: translateX(0);
        }
        
        .notification.success {
            border-left-color: var(--success);
        }
        
        .notification.error {
            border-left-color: var(--error);
        }
        
        .notification.warning {
            border-left-color: var(--warning);
        }
        
        .notification-icon {
            font-size: 1.5rem;
            color: var(--primary);
        }
        
        .notification.success .notification-icon {
            color: var(--success);
        }
        
        .notification.error .notification-icon {
            color: var(--error);
        }
        
        .notification.warning .notification-icon {
            color: var(--warning);
        }
        
        .notification-content {
            flex: 1;
        }
        
        .notification-title {
            font-weight: 600;
            color: var(--text-primary);
            margin-bottom: var(--spacing-xs);
        }
        
        .notification-message {
            font-size: 0.875rem;
            color: var(--text-secondary);
        }
        
        .notification-close {
            background: none;
            border: none;
            color: var(--text-secondary);
            cursor: pointer;
            padding: var(--spacing-xs);
            border-radius: var(--radius-sm);
            transition: var(--transition-fast);
        }
        
        .notification-close:hover {
            background: var(--background);
            color: var(--text-primary);
        }
        
        @media (max-width: 480px) {
            .notification {
                right: 10px;
                left: 10px;
                max-width: none;
            }
        }
    `;
    document.head.appendChild(notificationStyles);
    
    return notification;
}

// Close notification
function closeNotification() {
    const notification = document.getElementById('notification');
    if (notification) {
        notification.classList.remove('active');
    }
}

// Utility functions
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

// Add scroll-based animations for better performance
const debouncedScroll = debounce(() => {
    const scrolled = window.pageYOffset;
    const parallax = document.querySelectorAll('.floating-card');
    const speed = 0.5;
    
    parallax.forEach(element => {
        const yPos = -(scrolled * speed);
        element.style.transform = `translateY(${yPos}px)`;
    });
}, 10);

window.addEventListener('scroll', debouncedScroll);
