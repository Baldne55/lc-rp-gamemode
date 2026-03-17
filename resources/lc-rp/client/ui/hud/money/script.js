function formatAmount(n) {
    return n.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
}

Events.Subscribe('hud_money', function (cash, bank) {
    document.getElementById('cash-amount').textContent = '$' + formatAmount(cash);
    document.getElementById('bank-amount').textContent = '$' + formatAmount(bank);
});

Events.Subscribe('hudToggle', function (payload) {
    var visible = (Array.isArray(payload) && payload[0] !== undefined) ? payload[0] : payload;
    document.body.style.visibility = visible ? 'visible' : 'hidden';
});
