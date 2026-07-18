const switches = document.querySelectorAll(".switch");

switches.forEach((control) => {
  control.addEventListener("click", () => {
    const isOn = control.classList.toggle("is-on");
    control.setAttribute("aria-checked", String(isOn));
  });
});

const ruleButton = document.querySelector(".rule-button");
const ruleLabel = ruleButton?.querySelector("span");
const rules = ["Use default", "Reverse", "Standard"];
let ruleIndex = 0;

ruleButton?.addEventListener("click", () => {
  ruleIndex = (ruleIndex + 1) % rules.length;
  ruleLabel.textContent = rules[ruleIndex];
});
