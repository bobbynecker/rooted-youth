const button = document.querySelector('.menu-button');
const nav = document.querySelector('.site-nav');
const links = document.querySelectorAll('.site-nav a');

button.addEventListener('click', () => {
  const open = nav.classList.toggle('open');
  button.setAttribute('aria-expanded', open);
  button.setAttribute('aria-label', open ? 'Close navigation' : 'Open navigation');
});

links.forEach((link) => link.addEventListener('click', () => {
  nav.classList.remove('open');
  button.setAttribute('aria-expanded', 'false');
}));

const sections = [...document.querySelectorAll('main section[id], .contact[id]')];
const observer = new IntersectionObserver((entries) => {
  const active = entries.filter(entry => entry.isIntersecting).sort((a,b) => b.intersectionRatio - a.intersectionRatio)[0];
  if (!active) return;
  links.forEach(link => link.classList.toggle('active', link.getAttribute('href') === `#${active.target.id}`));
}, { threshold: 0.35 });
sections.forEach(section => observer.observe(section));
document.querySelector('#year').textContent = new Date().getFullYear();

document.querySelectorAll('.question-note-field').forEach((field) => {
  const key = field.dataset.noteKey;
  field.value = localStorage.getItem(key) || '';
  field.addEventListener('input', () => localStorage.setItem(key, field.value));
});
