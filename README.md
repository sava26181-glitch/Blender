# Neon Raid — 3D-модели (Blender)

Модели для мобильной игры «Неон-Рейд»: Болт (герой), Жук Роя (враг), ховербайк «Искра», Ядро лута.

`neon_raid.py` строит модели в Blender 4.2 и рендерит каждую в 4K (Cycles) с 6 сторон.
GitHub Actions (`.github/workflows/render.yml`) запускает рендер автоматически при пуше
или вручную: **Actions → Blender 4K Render → Run workflow**.

Результат — в артефактах сборки: PNG 4K, лист со всеми сторонами, `.blend`, `.glb`.
