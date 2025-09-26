// Contact Page JavaScript

document.addEventListener('DOMContentLoaded', function() {
    initContactForm();
    initFAQ();
});

// Contact form functionality
function initContactForm() {
    const form = document.getElementById('contactForm');
    const submitBtn = form.querySelector('.submit-btn');
    
    form.addEventListener('submit', function(e) {
        e.preventDefault();
        
        if (validateForm()) {
            submitForm();
        }
    });
    
    // Real-time validation
    const inputs = form.querySelectorAll('input, select, textarea');
    inputs.forEach(input => {
        input.addEventListener('blur', function() {
            validateField(this);
        });
        
        input.addEventListener('input', function() {
            clearFieldError(this);
        });
    });
}

// Form validation
function validateForm() {
    const form = document.getElementById('contactForm');
    const requiredFields = form.querySelectorAll('[required]');
    let isValid = true;
    
    requiredFields.forEach(field => {
        if (!validateField(field)) {
            isValid = false;
        }
    });
    
    // Validate email format
    const emailField = form.querySelector('#email');
    if (emailField.value && !isValidEmail(emailField.value)) {
        showFieldError(emailField, 'Por favor ingresa un email válido');
        isValid = false;
    }
    
    return isValid;
}

// Validate individual field
function validateField(field) {
    const value = field.value.trim();
    
    if (field.hasAttribute('required') && !value) {
        showFieldError(field, 'Este campo es requerido');
        return false;
    }
    
    if (field.type === 'email' && value && !isValidEmail(value)) {
        showFieldError(field, 'Por favor ingresa un email válido');
        return false;
    }
    
    clearFieldError(field);
    return true;
}

// Show field error
function showFieldError(field, message) {
    const formGroup = field.closest('.form-group');
    formGroup.classList.add('error');
    
    // Remove existing error message
    const existingError = formGroup.querySelector('.error-message');
    if (existingError) {
        existingError.remove();
    }
    
    // Add new error message
    const errorDiv = document.createElement('div');
    errorDiv.className = 'error-message';
    errorDiv.textContent = message;
    formGroup.appendChild(errorDiv);
}

// Clear field error
function clearFieldError(field) {
    const formGroup = field.closest('.form-group');
    formGroup.classList.remove('error');
    
    const errorMessage = formGroup.querySelector('.error-message');
    if (errorMessage) {
        errorMessage.remove();
    }
}

// Email validation
function isValidEmail(email) {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
}

// Submit form
function submitForm() {
    const form = document.getElementById('contactForm');
    const submitBtn = form.querySelector('.submit-btn');
    const formData = new FormData(form);
    
    // Show loading state
    submitBtn.classList.add('loading');
    submitBtn.disabled = true;
    
    const originalText = submitBtn.innerHTML;
    submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Enviando...';
    
    // Simulate form submission (replace with actual endpoint)
    setTimeout(() => {
        // Reset form
        form.reset();
        
        // Reset button
        submitBtn.classList.remove('loading');
        submitBtn.disabled = false;
        submitBtn.innerHTML = originalText;
        
        // Show success message
        showSuccessMessage();
        
        // Log form data (for development)
        console.log('Form submitted with data:', Object.fromEntries(formData));
        
    }, 2000);
}

// Show success message
function showSuccessMessage() {
    const successMessage = document.getElementById('successMessage');
    successMessage.classList.add('active');
    
    // Auto hide after 5 seconds
    setTimeout(() => {
        successMessage.classList.remove('active');
    }, 5000);
    
    // Close on click
    successMessage.addEventListener('click', function() {
        this.classList.remove('active');
    });
}

// FAQ functionality
function initFAQ() {
    const faqItems = document.querySelectorAll('.faq-item');
    
    faqItems.forEach(item => {
        const question = item.querySelector('.faq-question');
        
        question.addEventListener('click', function() {
            const isActive = item.classList.contains('active');
            
            // Close all other FAQ items
            faqItems.forEach(otherItem => {
                if (otherItem !== item) {
                    otherItem.classList.remove('active');
                }
            });
            
            // Toggle current item
            item.classList.toggle('active');
        });
    });
}

// Quick actions functionality
document.addEventListener('DOMContentLoaded', function() {
    const actionButtons = document.querySelectorAll('.action-btn');
    
    actionButtons.forEach(button => {
        button.addEventListener('click', function(e) {
            e.preventDefault();
            
            const buttonText = this.querySelector('span').textContent.toLowerCase();
            
            if (buttonText.includes('demo')) {
                requestDemo();
            } else if (buttonText.includes('tutorial')) {
                window.location.href = 'tutorials.html';
            } else if (buttonText.includes('descargar')) {
                // Use the download functionality from main.js
                if (typeof showDownloadModal === 'function') {
                    showDownloadModal('VentIQ Apps', 'both');
                }
            }
        });
    });
});

// Request demo functionality
function requestDemo() {
    // Pre-fill the contact form for demo request
    const form = document.getElementById('contactForm');
    const subjectSelect = form.querySelector('#subject');
    const messageTextarea = form.querySelector('#message');
    
    subjectSelect.value = 'demo';
    messageTextarea.value = 'Hola, me gustaría solicitar una demo de VentIQ para conocer mejor las funcionalidades del sistema. Por favor contáctenme para coordinar una presentación.';
    
    // Scroll to form
    form.scrollIntoView({ behavior: 'smooth', block: 'start' });
    
    // Focus on first name field
    setTimeout(() => {
        form.querySelector('#firstName').focus();
    }, 500);
    
    // Show notification
    if (typeof showNotification === 'function') {
        showNotification(
            'Formulario pre-llenado',
            'Hemos pre-llenado el formulario para solicitar una demo. Completa tus datos y envía la solicitud.',
            'info'
        );
    }
}

// Contact method interactions
document.addEventListener('DOMContentLoaded', function() {
    const contactMethods = document.querySelectorAll('.contact-method');
    
    contactMethods.forEach(method => {
        method.addEventListener('click', function() {
            const methodInfo = this.querySelector('.method-info');
            const icon = this.querySelector('.method-icon i');
            
            if (icon.classList.contains('fa-envelope')) {
                // Email
                window.location.href = 'mailto:contacto@ventiq.com';
            } else if (icon.classList.contains('fa-phone')) {
                // Phone
                window.location.href = 'tel:+15551234567';
            } else if (icon.classList.contains('fa-comments')) {
                // Chat
                showNotification(
                    'Chat en vivo',
                    'El chat en vivo estará disponible próximamente. Por ahora puedes contactarnos por email o teléfono.',
                    'info'
                );
            } else if (icon.classList.contains('fa-map-marker-alt')) {
                // Location
                showNotification(
                    'Ubicación',
                    'Para visitas presenciales, por favor agenda una cita previa contactándonos por email o teléfono.',
                    'info'
                );
            }
        });
    });
});

// Form auto-save (optional feature)
let autoSaveTimeout;

function initAutoSave() {
    const form = document.getElementById('contactForm');
    const inputs = form.querySelectorAll('input, select, textarea');
    
    inputs.forEach(input => {
        input.addEventListener('input', function() {
            clearTimeout(autoSaveTimeout);
            autoSaveTimeout = setTimeout(() => {
                saveFormData();
            }, 1000);
        });
    });
    
    // Load saved data on page load
    loadFormData();
}

function saveFormData() {
    const form = document.getElementById('contactForm');
    const formData = new FormData(form);
    const data = Object.fromEntries(formData);
    
    localStorage.setItem('ventiq_contact_form', JSON.stringify(data));
}

function loadFormData() {
    const savedData = localStorage.getItem('ventiq_contact_form');
    
    if (savedData) {
        const data = JSON.parse(savedData);
        const form = document.getElementById('contactForm');
        
        Object.keys(data).forEach(key => {
            const field = form.querySelector(`[name="${key}"]`);
            if (field) {
                if (field.type === 'checkbox') {
                    field.checked = data[key] === 'on';
                } else {
                    field.value = data[key];
                }
            }
        });
    }
}

function clearFormData() {
    localStorage.removeItem('ventiq_contact_form');
}

// Initialize auto-save
document.addEventListener('DOMContentLoaded', function() {
    initAutoSave();
});

// Clear saved data when form is successfully submitted
function showSuccessMessage() {
    const successMessage = document.getElementById('successMessage');
    successMessage.classList.add('active');
    
    // Clear saved form data
    clearFormData();
    
    // Auto hide after 5 seconds
    setTimeout(() => {
        successMessage.classList.remove('active');
    }, 5000);
    
    // Close on click
    successMessage.addEventListener('click', function() {
        this.classList.remove('active');
    });
}
