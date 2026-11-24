const favicon = document.getElementById('favicon');
const lightIcon = favicon.getAttribute('href');
const darkMode = window.matchMedia('(prefers-color-scheme: dark)');

function updateFavicon() {
  favicon.href = darkMode.matches ? favicon.dataset.dark : lightIcon;
}

updateFavicon();
darkMode.addEventListener('change', updateFavicon);
