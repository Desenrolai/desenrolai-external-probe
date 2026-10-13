#!/usr/bin/env bash
# Sonda EXTERNA de disponibilidade (PLAT-158).
#
# Lê de ALVOS uma linha por endpoint, no formato `<url> <esperado>`, onde
# `esperado` é um código HTTP exato (ex.: 200) ou `2xx3xx`. Linhas vazias e
# começadas por `#` são ignoradas. Sai 1 se algum endpoint estiver fora depois
# de TENTATIVAS tentativas; sai 2 se a configuração for inválida ou vazia.
#
# ⚠️ O LOG DESTE SCRIPT É PÚBLICO (roda num repositório público). Ele imprime
# só host, código e latência: nunca o corpo (`-o /dev/null`), nunca o IP
# resolvido (sem `%{remote_ip}` no `-w`), nunca o stderr do curl (que cita o
# endereço em erros de conexão).
#
# Redirect NÃO é seguido: um 302 ou 307 para uma tela de login conta como o
# código que é, e quem aceita 3xx diz isso explicitamente com `2xx3xx`.
set -uo pipefail
set +x

TENTATIVAS="${TENTATIVAS:-3}"
INTERVALO="${INTERVALO:-15}"
TIMEOUT="${TIMEOUT:-10}"
SONDA_RESUMO="${SONDA_RESUMO:-/dev/null}"
GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/null}"

erro_de_configuracao() {
  echo "::error title=Sonda mal configurada::$1"
  exit 2
}

for numero in "$TENTATIVAS" "$INTERVALO" "$TIMEOUT"; do
  [[ "$numero" =~ ^[0-9]+$ ]] || erro_de_configuracao "TENTATIVAS/INTERVALO/TIMEOUT precisam ser inteiros"
done
[ "$TENTATIVAS" -ge 1 ] || erro_de_configuracao "TENTATIVAS precisa ser >= 1"

codigo_aceito() {
  local codigo="$1" esperado="$2"
  if [ "$esperado" = "2xx3xx" ]; then
    [[ "$codigo" =~ ^[23][0-9][0-9]$ ]]
  else
    [ "$codigo" = "$esperado" ]
  fi
}

# Uma tentativa: imprime "<codigo> <latencia_ms>". Código 000 = sem resposta
# (DNS, conexão recusada, TLS, timeout).
medir() {
  local url="$1" medida codigo segundos
  medida="$(curl -s -o /dev/null --max-time "$TIMEOUT" --proto '=https,http' \
              -w '%{http_code} %{time_total}' "$url" 2>/dev/null)" || true
  codigo="${medida%% *}"
  segundos="${medida##* }"
  [[ "$codigo" =~ ^[0-9]{3}$ ]] || codigo="000"
  [[ "$segundos" =~ ^[0-9]+([.,][0-9]+)?$ ]] || segundos="0"
  printf '%s %d\n' "$codigo" "$(awk -v s="${segundos/,/.}" 'BEGIN { printf "%d", s * 1000 }')"
}

alvos=0
falhas=()
linhas_resumo=()

while IFS= read -r linha || [ -n "$linha" ]; do
  linha="${linha%%#*}"
  read -r url esperado sobra <<<"$linha" || true
  [ -z "${url:-}" ] && continue
  [ -z "${sobra:-}" ] || erro_de_configuracao "alvo com campos demais (esperado: <url> <código>)"
  [[ "$url" =~ ^https?://([A-Za-z0-9.-]+)(:[0-9]+)?(/.*)?$ ]] \
    || erro_de_configuracao "alvo com URL inválida (só http/https)"
  host="${BASH_REMATCH[1]}"
  [[ "${esperado:-}" =~ ^([1-5][0-9][0-9]|2xx3xx)$ ]] \
    || erro_de_configuracao "alvo sem código esperado válido (código HTTP ou 2xx3xx)"
  alvos=$((alvos + 1))

  tentativa=1
  while :; do
    read -r codigo latencia <<<"$(medir "$url")"
    if codigo_aceito "$codigo" "$esperado"; then
      echo "ok ${host} ${codigo} ${latencia}ms tentativa ${tentativa}/${TENTATIVAS}"
      linhas_resumo+=("| ${host} | ${codigo} | ${latencia} ms | ok |")
      break
    fi
    if [ "$tentativa" -ge "$TENTATIVAS" ]; then
      echo "FALHA ${host} ${codigo} ${latencia}ms esperado=${esperado} tentativas=${TENTATIVAS}"
      echo "::error title=Serviço fora do ar::${host} respondeu ${codigo} (esperado ${esperado}) em ${TENTATIVAS} tentativa(s)"
      linhas_resumo+=("| ${host} | ${codigo} | ${latencia} ms | **FORA** (esperado ${esperado}) |")
      falhas+=("$host")
      break
    fi
    tentativa=$((tentativa + 1))
    sleep "$INTERVALO"
  done
done <<<"${ALVOS:-}"

# Zero alvos não é zero falhas: uma sonda que não mediu nada não pode ficar verde.
[ "$alvos" -gt 0 ] || erro_de_configuracao "ALVOS vazio: nenhum endpoint sondado"

lista_falhas="$(printf '%s\n' "${falhas[@]+"${falhas[@]}"}" | sed '/^$/d' | sort -u | paste -sd, -)"
echo "falhas=${lista_falhas}" >>"$GITHUB_OUTPUT"
{
  echo "| host | código | latência | estado |"
  echo "|---|---|---|---|"
  printf '%s\n' "${linhas_resumo[@]+"${linhas_resumo[@]}"}"
} >"$SONDA_RESUMO"

if [ "${#falhas[@]}" -gt 0 ]; then
  echo "${#falhas[@]} de ${alvos} endpoint(s) fora do ar."
  exit 1
fi
echo "${alvos} endpoint(s) no ar."
