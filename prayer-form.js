(() => {
  'use strict';

  const prayerForm = document.querySelector('#prayer-request-form');
  const prayerStatus = document.querySelector('.form-status');
  if (!prayerForm || !prayerStatus) return;

  const submitButton = prayerForm.querySelector('button[type="submit"]');
  const honeypotField = prayerForm.elements.namedItem('_gotcha');

  window.addEventListener('pageshow', (event) => {
    if (event.persisted) prayerForm.reset();
  });

  prayerForm.addEventListener('submit', async (event) => {
    event.preventDefault();
    const messageField = document.querySelector('#prayer-message');
    const consentField = document.querySelector('#prayer-consent');

    if (!prayerForm.checkValidity()) {
      prayerForm.reportValidity();
      prayerStatus.textContent = 'Please complete the required fields before submitting.';
      return;
    }
    if (!messageField.value.trim()) {
      prayerStatus.textContent = 'Please write a prayer request before submitting.';
      messageField.focus();
      return;
    }
    if (!consentField.checked) {
      prayerStatus.textContent = 'Please read and accept the privacy notice before submitting.';
      consentField.focus();
      return;
    }

    if (honeypotField && honeypotField.value) {
      prayerForm.reset();
      window.location.replace('prayer-thank-you.html');
      return;
    }

    const controller = new AbortController();
    const requestTimeout = window.setTimeout(() => controller.abort(), 15000);
    prayerStatus.textContent = 'Sending your private prayer request\u2026';
    submitButton.disabled = true;
    try {
      const response = await fetch(prayerForm.action, {
        method: 'POST',
        body: new FormData(prayerForm),
        headers: { Accept: 'application/json' },
        cache: 'no-store',
        credentials: 'omit',
        referrerPolicy: 'no-referrer',
        signal: controller.signal
      });
      if (!response.ok) throw new Error('Unable to send request');
      prayerForm.reset();
      window.location.replace('prayer-thank-you.html');
    } catch (error) {
      prayerStatus.textContent = 'Your request could not be sent right now. Please try again.';
      submitButton.disabled = false;
    } finally {
      window.clearTimeout(requestTimeout);
    }
  });
})();
