# OGSR SDK на этом ПК

Рабочая игра: `C:\razrabotka\ogsr-project\game`.
Чистый SDK: `C:\razrabotka\ogsr-sdk` (OGSR & B.O.R.S.C.H.T SOC, сборка 01.10.2026).
Компиляторы: SkyLoader Universal Compiler 1.6b x64.
Исходный SDK и проект в `sdk-soc` сохранены.

## Редактор и сборка уровня

1. Запустить `C:\razrabotka\ogsr-sdk\Start-Level-Editor.cmd`.
2. File → Open Scene. Доступны `maps\mp_atp_test.level`, `maps\mp_atp.level` и восстановленная `maps\l07_military.level`.
3. Модели `.object`: `rawdata\objects`; текстуры DDS/THM: `rawdata\textures`; игровые текстуры: `gamedata\textures`.
4. После изменения статической геометрии включить объект в правильный сектор. Для наружных объектов — сектор DEFAULT; для комнаты — её сектор.
5. Сохранить сцену и выполнить Build → Build Scene. Это экспортирует `build.prj` в `gamedata\levels\имя_уровня`.
6. Запустить `Compile-Level-Quality.cmd` и ввести имя папки уровня. Для Складов есть `Compile-Military-Quality.cmd`. Дождаться `BUILD OK`.
7. Для замены геометрии Складов закрыть игру и запустить `Deploy-Military.cmd`.

`Compile-Level-Draft.cmd` создаёт быстрый вариант без освещения; для обычной игры использовать Quality.
Компиляция запускается отдельной командой: встроенный вызов Compile в этой версии редактора может падать при повторном запуске.

PowerShell, пример для Складов:

```powershell
cd C:\razrabotka\ogsr-sdk
.\Compile-Level.ps1 -Level l07_military
.\Deploy-Level.ps1 -Level l07_military             # сначала просмотр
.\Deploy-Level.ps1 -Level l07_military -Apply      # установка с резервной копией
```

Установщик проверяет успешный журнал, переносит геометрию, коллизию, свет, связанные текстуры и HOM. Резервные копии находятся в `backup\deploy-*`, копии сверяются по SHA-256.
При обновлении существующей локации её сюжетный spawn и AI-графы сохраняются. Если меняется проходимость или навигация, AI и спавн нужно пересобрать отдельно.

## AI, трава и новая локация

```powershell
.\Compile-Level.ps1 -Level my_level -Stage AI
.\Compile-Level.ps1 -Level my_level -Stage VerifyAI
.\Compile-Level.ps1 -Level my_level -Stage Details
.\Compile-Level.ps1 -Level my_level -Stage Spawn -SpawnLevels my_level
.\Deploy-Level.ps1 -Level my_level -Package -Apply
```

AI сначала надо создать и экспортировать в редакторе. Сборщик спавна пишет отдельный `my_level_sdk.spawn`; он автоматически включает ключ расширенного AI, если все выбранные уровни имеют этот формат.
Для текущей сюжетной базы использовать обычный формат AI, совпадающий с остальными уровнями. Расширенный формат нельзя смешивать с оригинальными сетками в одной сборке спавна.

Пакет нового уровня появится в `C:\razrabotka\ogsr-project\level-builds\my_level\gamedata`. Для включения новой сюжетной локации также нужны записи в `game_levels.ltx` / `game_maps_single.ltx`, граф-поинты, объединённый game.graph/cross-table, включение объектов в all.spawn и переходы. Эта часть зависит от самой локации и её сюжета; простого копирования папки недостаточно. Исходники сцен новой локации сохранять отдельно от `level-builds` — это папка результатов компиляции, исключённая из Git.

Для текущего сюжета сборка уже настроена:

```powershell
cd C:\razrabotka\ogsr-project
.\tools\build_all.ps1 -NoDeploy   # проверить сборку без установки
.\tools\build_all.ps1             # собрать и установить сюжет
```

После изменения all.spawn тестировать с новой игры. `Run-Game.cmd` открывает меню вашей OGSR-игры.

## GitHub

Репозиторий: https://github.com/ilya4ever/amk-project
Рабочая Git-папка: `C:\razrabotka\ogsr-project`.
Аккаунт Git Credential Manager: `ilya4ever`; автор коммитов взят из существующей истории проекта.
Актуальная OGSR-версия объединена с прежней историей репозитория в `main` обычным
merge без переписывания коммитов. Исходники текущей версии — `story/gamedata`,
инструменты — `tools`; сохранённые корневые игровые папки относятся к прежней
AMK-версии. Для дальнейшей работы создавайте отдельную ветку от `main`.

```powershell
cd C:\razrabotka\ogsr-project
git status
git add story tools docs README.md .gitignore
git diff --cached --stat
git commit -m "Set up OGSR project and SDK workflow on this PC"
git push -u origin HEAD
```

Авторизация Git Credential Manager настроена. Сохранения, установленная игра,
скачанные архивы, результаты сборки и резервные копии исключены из Git.
Папка SDK находится рядом с Git-проектом: для сохранения своих сцен/моделей в Git их надо поместить в проект, например `sdk-source`, и отдельно добавить. Компилированные игровые файлы и скачанные SDK-библиотеки в Git не нужны.

Версионные копии команд находятся в `tools\sdk`: после переноса проекта их нужно скопировать в корень установленного `ogsr-sdk` и запускать оттуда.

## Проверки установки

- Геометрия Складов: тестовая компиляция успешно завершена.
- AI Складов: тестовая компиляция успешно завершена; результат оставлен в SDK.
- Пример `mp_atp_test`: полная компиляция со светом успешно завершена.
- Проверено создание пакета `level-builds\mp_atp_test` с недостающими текстурами.
- В восстановленной сцене проверены 1596 ссылок на модели — все `.object` присутствуют.
- Сюжет проекта: `build_all.ps1 -NoDeploy` успешно создал all.spawn.
- После Escape пользователя автоматическое управление редактором было остановлено. Экспорт Build Scene через интерфейс в этом сеансе не проверен; тест компиляторов выполнен по имеющимся build.prj.

Восстановленная сцена Складов получается обратным преобразованием игровой геометрии. Потерянные оригинальные авторские .object/.level со старого ПК побитно не восстановить; пользовательский asset pack и исходная библиотека SDK установлены заново.
Пресеты погоды, для которых нет текстур ЧН/ЗП, сохранены в `backup\weather-presets-without-textures`; для работы оставлена погода с установленными ресурсами ТЧ.

Источники: [тема OGSR SDK](https://ap-pro.ru/forums/topic/14338-ogsr-borscht-sdk/), [Universal ACDC автора](https://github.com/abramcumner/universal_acdc), [XDB-плагин OGSR](https://github.com/OGSR/xray-db-7z-plugin).
