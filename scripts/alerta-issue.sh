#!/usr/bin/env bash
# Transforma o resultado da sonda de disponibilidade num sinal PERSISTENTE: uma
# única issue no repositório, aberta enquanto houver serviço fora (PLAT-158).
#
# O e-mail de falha de workflow agendado vai só para quem editou o cron por
# último, e para de chegar se essa pessoa sair da org. A issue é notificável
# para qualquer watcher e fica visível até alguém (ou o próximo run verde)
# fechá-la.
#
#   falha,   sem issue aberta  -> reabre a última fechada pelo bot, ou cria uma
#   falha,   issue aberta      -> comenta SÓ se o conjunto de hosts mudou
#                                 (a cada 10 min por 3 dias seriam ~430 e-mails)
#   sucesso, issue aberta      -> comenta "normalizado" e fecha
#   sucesso, sem issue aberta  -> nada
#
# A issue é achada pela label exclusiva LABEL, filtrada no servidor: o volume
# de issues do repositório não afeta a busca e não há página a percorrer. Além
# da label, só issues de github-actions[bot] contam: o repositório é público e
# qualquer pessoa pode abrir uma issue com o mesmo título.
#
# Entrada (env): GITHUB_REPOSITORY, RESULTADO (sucesso|falha), FALHAS (hosts
# separados por vírgula), SONDA_RESUMO (tabela markdown), RUN_URL, MENCIONAR
# (opcional, ex.: "@fulano @time").
set -euo pipefail
set +x

TITULO="Sonda de disponibilidade: serviço fora do ar"
BOT="github-actions[bot]"
LABEL="sonda-disponibilidade"
REPO="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY ausente}"
RESULTADO="${RESULTADO:-}"
FALHAS="${FALHAS:-}"
RUN_URL="${RUN_URL:-}"
MENCIONAR="${MENCIONAR:-}"
SONDA_RESUMO="${SONDA_RESUMO:-/dev/null}"

case "$RESULTADO" in
  sucesso|falha) ;;
  *) echo "::error::RESULTADO precisa ser 'sucesso' ou 'falha'"; exit 2 ;;
esac

# Run que falhou sem produzir lista (ex.: script não rodou) ainda é falha.
[ "$RESULTADO" = "falha" ] && [ -z "$FALHAS" ] && FALHAS="sonda-sem-resultado"

tmp="$(mktemp -d)"
trap 'rm -f -- "$tmp/corpo.md" "$tmp/comentario.md"; rmdir -- "$tmp"' EXIT

# Imprime "<numero> <falhas-registradas>" da issue mais recente do bot nesse estado.
# A seleção é em python3 (presente no runner hospedado), não em `--jq`, para o
# teste do infra exercitar este filtro com um `gh` falso.
issue_do_bot() {
  gh api --method GET "repos/${REPO}/issues" -f state="$1" -f labels="$LABEL" \
    -f sort=updated -f direction=desc -f per_page=20 \
  | TITULO="$TITULO" BOT="$BOT" python3 -c '
import json, os, re, sys
for issue in json.load(sys.stdin):
    if ("pull_request" not in issue and issue.get("title") == os.environ["TITULO"]
            and (issue.get("user") or {}).get("login") == os.environ["BOT"]):
        marca = re.search(r"<!-- sonda-falhas: (\S*) -->", issue.get("body") or "")
        print(issue["number"], marca.group(1) if marca else "")
        break
'
}

escrever_corpo() {
  {
    echo "Serviço(s) fora do ar segundo a sonda externa: \`${FALHAS}\`."
    echo
    cat "$SONDA_RESUMO"
    echo
    echo "Run: ${RUN_URL}"
    [ -n "$MENCIONAR" ] && echo && echo "cc ${MENCIONAR}"
    echo
    echo "Esta issue fecha sozinha no primeiro run verde."
    echo "<!-- sonda-falhas: ${FALHAS} -->"
  } >"$tmp/corpo.md"
}

comentar() {
  printf '%s\n\n' "$1" >"$tmp/comentario.md"
  cat "$SONDA_RESUMO" >>"$tmp/comentario.md"
  printf '\nRun: %s\n' "$RUN_URL" >>"$tmp/comentario.md"
  gh api --method POST "repos/${REPO}/issues/$2/comments" -F body=@"$tmp/comentario.md" >/dev/null
}

aberta="$(issue_do_bot open)"
numero="${aberta%% *}"
registradas="${aberta#* }"

if [ "$RESULTADO" = "sucesso" ]; then
  if [ -z "$aberta" ]; then
    echo "Tudo no ar e nenhuma issue aberta: nada a fazer."
    exit 0
  fi
  comentar "Normalizado: todos os endpoints voltaram a responder." "$numero"
  gh api --method PATCH "repos/${REPO}/issues/${numero}" -f state=closed \
    -f state_reason=completed >/dev/null
  echo "Issue #${numero} fechada."
  exit 0
fi

escrever_corpo
if [ -n "$aberta" ]; then
  if [ "$registradas" = "$FALHAS" ]; then
    echo "Issue #${numero} já registra as mesmas falhas (${FALHAS}): sem comentário novo."
    exit 0
  fi
  comentar "Mudou o conjunto de serviços fora: \`${registradas}\` -> \`${FALHAS}\`." "$numero"
  gh api --method PATCH "repos/${REPO}/issues/${numero}" -F body=@"$tmp/corpo.md" >/dev/null
  echo "Issue #${numero} atualizada."
  exit 0
fi

fechada="$(issue_do_bot closed)"
if [ -n "$fechada" ]; then
  numero="${fechada%% *}"
  gh api --method PATCH "repos/${REPO}/issues/${numero}" -f state=open \
    -F body=@"$tmp/corpo.md" >/dev/null
  comentar "Reaberta: serviço(s) fora do ar de novo (\`${FALHAS}\`)." "$numero"
  echo "Issue #${numero} reaberta."
  exit 0
fi

# Primeira issue do repositório: a label ainda não existe. GET antes de POST
# para não confundir "já existe" (422) com erro real.
if ! gh api "repos/${REPO}/labels/${LABEL}" >/dev/null 2>&1; then
  gh api --method POST "repos/${REPO}/labels" -f name="$LABEL" -f color=B60205 \
    -f description="Alerta da sonda externa de disponibilidade" >/dev/null
fi
# O GitHub DESCARTA em silêncio a label que o token não pode aplicar e cria a
# issue mesmo assim. Sem a label, o próximo run não a acha e abre outra: uma
# issue nova a cada 10 min. Por isso a resposta é conferida, e a falha é alta.
criada="$(gh api --method POST "repos/${REPO}/issues" -f title="$TITULO" \
  -f "labels[]=${LABEL}" -F body=@"$tmp/corpo.md")"
if ! LABEL="$LABEL" python3 -c '
import json, os, sys
issue = json.load(sys.stdin)
sys.exit(0 if os.environ["LABEL"] in [l.get("name") for l in issue.get("labels") or []] else 1)
' <<<"$criada"; then
  echo "::error title=Issue sem label::a issue foi criada sem a label ${LABEL}; o próximo run abriria outra"
  exit 1
fi
echo "Issue criada."
