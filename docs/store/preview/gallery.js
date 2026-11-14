"use strict";
document.querySelectorAll("[data-shot]").forEach(function (button) {
  button.addEventListener("click", function () {
    document.querySelectorAll("[data-shot]").forEach(function (other) { other.classList.remove("active"); other.setAttribute("aria-pressed", "false"); });
    button.classList.add("active"); button.setAttribute("aria-pressed", "true");
    var path = "media/" + button.dataset.shot;
    var image = document.getElementById("main-shot"); image.src = path; image.alt = button.dataset.alt;
    document.getElementById("full-shot").href = path;
    document.getElementById("shot-caption").textContent = button.dataset.caption;
  });
});
