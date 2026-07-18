const switches = document.querySelectorAll(".switch");

switches.forEach((control) => {
  control.addEventListener("click", () => {
    const isOn = control.classList.toggle("is-on");
    control.setAttribute("aria-checked", String(isOn));
  });
});
