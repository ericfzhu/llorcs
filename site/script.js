const switches = document.querySelectorAll(".switch");

switches.forEach((control) => {
  control.addEventListener("click", () => {
    const isOn = control.classList.toggle("is-on");
    control.setAttribute("aria-checked", String(isOn));
  });
});

const ruleMenu = document.querySelector(".rule-menu");

if (ruleMenu) {
  const trigger = ruleMenu.querySelector(".rule-trigger");
  const value = ruleMenu.querySelector(".rule-value");
  const popover = ruleMenu.querySelector(".rule-popover");
  const options = [...ruleMenu.querySelectorAll(".rule-option")];

  const selectedOption = () =>
    options.find((option) => option.getAttribute("aria-checked") === "true");

  const setOpen = (isOpen) => {
    ruleMenu.classList.toggle("is-open", isOpen);
    trigger.setAttribute("aria-expanded", String(isOpen));
    popover.setAttribute("aria-hidden", String(!isOpen));
  };

  const moveFocus = (direction) => {
    const currentIndex = Math.max(options.indexOf(document.activeElement), 0);
    const nextIndex = (currentIndex + direction + options.length) % options.length;
    options[nextIndex].focus();
  };

  trigger.addEventListener("click", () => {
    const willOpen = !ruleMenu.classList.contains("is-open");
    setOpen(willOpen);

    if (willOpen) {
      selectedOption()?.focus();
    }
  });

  trigger.addEventListener("keydown", (event) => {
    if (!["ArrowDown", "ArrowUp"].includes(event.key)) return;

    event.preventDefault();
    setOpen(true);
    const target =
      event.key === "ArrowUp" ? options.at(-1) : selectedOption() || options[0];
    target.focus();
  });

  options.forEach((option) => {
    option.addEventListener("click", () => {
      options.forEach((item) => {
        const isSelected = item === option;
        item.classList.toggle("is-selected", isSelected);
        item.setAttribute("aria-checked", String(isSelected));
      });

      value.textContent = option.dataset.label;
      setOpen(false);
      trigger.focus();
    });

    option.addEventListener("keydown", (event) => {
      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        moveFocus(event.key === "ArrowDown" ? 1 : -1);
      } else if (event.key === "Home" || event.key === "End") {
        event.preventDefault();
        options[event.key === "Home" ? 0 : options.length - 1].focus();
      } else if (event.key === "Escape") {
        event.preventDefault();
        setOpen(false);
        trigger.focus();
      } else if (event.key === "Tab") {
        setOpen(false);
      }
    });
  });

  document.addEventListener("pointerdown", (event) => {
    if (!ruleMenu.contains(event.target)) setOpen(false);
  });
}
