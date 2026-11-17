// Checklists onthouden op deze telefoon + offline werken
(function () {
  function load(k) { try { return JSON.parse(localStorage.getItem("danny-" + k) || "[]"); } catch (e) { return []; } }
  function save(k, v) { try { localStorage.setItem("danny-" + k, JSON.stringify(v)); } catch (e) {} }
  document.querySelectorAll(".checklist").forEach(function (box) {
    var key = box.dataset.key;
    var inputs = Array.prototype.slice.call(box.querySelectorAll("input[type=checkbox]"));
    var count = box.querySelector(".check-count");
    var state = load(key);
    inputs.forEach(function (inp, i) { inp.checked = !!state[i]; });
    function update() {
      var n = inputs.filter(function (x) { return x.checked; }).length;
      count.textContent = n + " van " + inputs.length + " gedaan";
      box.classList.toggle("done", n === inputs.length);
      save(key, inputs.map(function (x) { return x.checked; }));
    }
    inputs.forEach(function (inp) { inp.addEventListener("change", update); });
    box.querySelector(".check-reset").addEventListener("click", function () {
      inputs.forEach(function (x) { x.checked = false; }); update();
    });
    update();
  });
  // Service worker alleen op de echte website (niet in een voorbeeldweergave)
  try {
    if ("serviceWorker" in navigator && location.protocol === "https:" && window.top === window.self) {
      navigator.serviceWorker.register("sw.js").catch(function () {});
    }
  } catch (e) {}
})();
