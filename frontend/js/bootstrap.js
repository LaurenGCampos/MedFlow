const modulePath=['workspace','track','invite'].includes(document.body.dataset.page)?'./operations.js':'./app.js';
import(modulePath).catch(() => { const message = document.querySelector('#message'); if (message) { message.textContent = 'Não foi possível carregar o sistema. Confira a configuração pública e a conexão.'; message.className = 'notice error'; } });
