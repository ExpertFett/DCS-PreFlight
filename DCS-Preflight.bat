@echo off
title DCS Pre-Flight Launcher
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0DCS-Preflight.ps1" %*
