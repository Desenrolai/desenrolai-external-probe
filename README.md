# desenrolai-external-probe

Sondas externas da Desenrolai: superfície de rede e disponibilidade.

Este repositório contém **dois workflows**, ambos rodando de fora da nossa rede:

- `external-surface-audit.yml` — de 6 em 6 horas pergunta se os endereços
  públicos da nossa infraestrutura respondem apenas nas portas que declaramos
  como públicas, e falha se algo a mais estiver aceitando conexão, ou se um
  ponto de entrada declarado parar de responder.
- `sonda-disponibilidade.yml` — a cada 10 minutos faz um GET nos endpoints
  públicos críticos (API, Bio, Plane, Infisical, Forge) e falha se algum não
  responder o código esperado depois de 3 tentativas. Enquanto houver serviço
  fora, mantém **uma** issue aberta neste repositório, e a fecha sozinha no
  primeiro run verde. O log mostra só hostname, código HTTP e latência.

## Por que ele mora num repositório separado

A pergunta que este controle responde é *"isto está alcançável pela internet?"*.
Uma sonda que roda **dentro** da rede auditada não consegue respondê-la: o que
distingue os dois casos é o endereço de origem do pacote, não o teste em si.
Nossos executores de CI próprios rodam dentro dessa mesma rede, então o
workflow precisa de um runner hospedado pelo GitHub — um ponto de observação
genuinamente externo.

Ele fica aqui, separado e público, porque runners hospedados estão disponíveis
para repositórios públicos.

## Por que a sonda de disponibilidade também mora aqui

Nosso monitoramento roda dentro da mesma infraestrutura que monitora. Quando
ela cai inteira, o monitoramento cai junto e ninguém é avisado. Esta sonda é o
observador que não cai junto.

## O que este repositório NÃO contém

Nenhum endereço, credencial ou detalhe de topologia. Os endereços auditados são
segredos do repositório, e os logos de execução são públicos — por isso o
workflow:

- registra `::add-mask::` para cada endereço **antes de qualquer outro passo**,
  de modo que nada que vá para o log possa conter um deles;
- identifica os alvos por **índice posicional** (`node-1`, `node-2`), nunca por
  hash do endereço. Um hash sem sal de um endereço IPv4 é reversível por força
  bruta em minutos — num log público isso seria codificação, não anonimização.

Se você encontrar qualquer endereço concreto na saída de uma execução, isso é um
defeito e gostaríamos de saber: abra uma issue, ou escreva para
`contato@desenrol.ai`.

## Manutenção

A fonte versionada deste workflow, com o histórico da decisão e o gate que
impede que ele volte a rodar num executor interno, vive no repositório privado
de infraestrutura da Desenrolai, em `sonda-externa-publica/`. Mudanças começam
por lá.
