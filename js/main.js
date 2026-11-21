document.documentElement.classList.add('js');

/* Класс `js` ставим самой первой строкой и намеренно вне IIFE: CSS прячет
   .reveal только при наличии класса на <html>. Скрипт подключён в конце
   <body>, поэтому задержка здесь = короткая вспышка видимого контента. */

(function () {
  'use strict';

  // Год в подвале. Элемент ищем защитно: если разметку подрежут или скрипт
  // подключат на другой странице — молча выходим, а не роняем выполнение.
  const year = document.getElementById('yr');
  if (year) {
    year.textContent = new Date().getFullYear();
  }

  const reveal = document.querySelectorAll('.reveal');
  // Нечего показывать — наблюдать тоже не за чем, экономим работу.
  if (!reveal.length) {
    return;
  }

  // Показать всё разом. Нужно в двух случаях: нет IntersectionObserver и
  // пользователь просил не анимировать. В обоих наблюдение бессмысленно.
  const showAll = () => {
    for (let i = 0; i < reveal.length; i++) {
      reveal[i].classList.add('on');
    }
  };

  // Уважаем системную настройку «меньше движения»: контент отдаём сразу,
  // без анимации появления — это и правильнее, и дешевле.
  let reduceMotion = false;
  try {
    reduceMotion = Boolean(
      window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches
    );
  } catch (e) {
    reduceMotion = false;
  }
  if (reduceMotion) {
    showAll();
    return;
  }

  // Запасной путь для браузеров без IntersectionObserver (старый Safari).
  if (!('IntersectionObserver' in window)) {
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

  for (let i = 0; i < reveal.length; i++) {
    io.observe(reveal[i]);
  }
})();
