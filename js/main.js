document.documentElement.classList.add('js');

/* Класс `js` ставим самой первой строкой и намеренно вне IIFE: CSS прячет
   .reveal только при наличии класса на <html>. Скрипт подключён в конце
   <body>, поэтому задержка здесь = короткая вспышка видимого контента. */

(function () {
  'use strict';

  // ——— системная настройка «меньше движения» ———
  // Читаем один раз: понадобится и для появления блоков, и для подарков.
  let reduceMotion = false;
  try {
    reduceMotion = Boolean(
      window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches
    );
  } catch (e) {
    reduceMotion = false;
  }

  // ——— год в подвале ———
  // Элемент ищем защитно: если разметку подрежут или скрипт подключат на
  // другой странице — молча идём дальше, а не роняем выполнение.
  const year = document.getElementById('yr');
  if (year) {
    year.textContent = new Date().getFullYear();
  }

  // ——— появление блоков при скролле ———
  setupReveal(reduceMotion);

  // ——— анимации уникальных подарков ———
  // Отдельным вызовом, а не внутри setupReveal: у появления и у подарков
  // разные условия, и один не должен отменять другой.
  setupGifts(reduceMotion);

  /* ---------------------------------------------------------------
     Появление блоков. Скрываем ТОЛЬКО когда html.js — класс ставит
     скрипт в начале, поэтому без JS (или если скрипт отрезал блокировщик)
     контент виден сразу, а не остаётся навсегда прозрачным.
     --------------------------------------------------------------- */
  function setupReveal(reduceMotion) {
    const items = document.querySelectorAll('.reveal');
    if (!items.length) {
      return;
    }

    const showAll = () => {
      for (let i = 0; i < items.length; i++) {
        items[i].classList.add('on');
      }
    };

    // Движение выключено или IntersectionObserver нет (старый Safari) —
    // показываем всё разом, наблюдение бессмысленно.
    if (reduceMotion || !('IntersectionObserver' in window)) {
      showAll();
      return;
    }

    const io = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('on');
          // Отписываемся сразу: блок показывается один раз, держать его
          // в наблюдении до конца жизни страницы незачем.
          io.unobserve(entry.target);
        }
      });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });

    for (let i = 0; i < items.length; i++) {
      io.observe(items[i]);
    }
  }

  /* ---------------------------------------------------------------
     Уникальные подарки в Telegram анимированные — это Lottie-файлы,
     снятые с самого подарка. Значит, их можно проиграть один в один.

     В разметке уже лежит статичная картинка .webp, и она остаётся
     основным содержимым: если библиотека не загрузилась (CDN закрыт,
     старый браузер), посетитель всё равно увидит подарок.

     Проигрываем только пока блок в поле зрения. Три одновременные
     анимации на телефоне греют батарею и роняют кадры.
     --------------------------------------------------------------- */
  function setupGifts(reduceMotion) {
    const slots = document.querySelectorAll('[data-lottie]');
    if (!slots.length || typeof window.lottie === 'undefined') {
      return;                         // остаются статичные .webp
    }

    for (let i = 0; i < slots.length; i++) {
      const slot = slots[i];

      const anim = window.lottie.loadAnimation({
        container: slot,
        renderer: 'svg',
        loop: true,
        autoplay: false,              // пустим, когда карточка войдёт в кадр
        path: slot.getAttribute('data-lottie')
      });

      // Прячем статичную картинку только после того, как Lottie отрисовал
      // первый кадр: иначе будет мигание пустой рамкой.
      anim.addEventListener('DOMLoaded', () => {
        slot.classList.add('is-live');
      });

      // «Меньше движения» — показываем один статичный кадр и не играем.
      if (reduceMotion) {
        continue;
      }

      playWhileVisible(slot, anim);
    }
  }

  /* Запуск и пауза по видимости. Без IntersectionObserver просто играем. */
  function playWhileVisible(slot, anim) {
    if (!('IntersectionObserver' in window)) {
      anim.play();
      return;
    }

    const vis = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          anim.play();
        } else {
          anim.pause();               // ушло с экрана — не тратим кадры
        }
      });
    }, { threshold: 0.15 });

    vis.observe(slot);
  }
})();
