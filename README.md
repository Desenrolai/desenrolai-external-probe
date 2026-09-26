# desenrolai-external-probe

Sonda externa da superfície de rede da Desenrolai.

Este repositório contém **um único workflow**. De 6 em 6 horas ele pergunta, de
fora da nossa rede, se os endereços públicos da nossa infraestrutura respondem
apenas nas portas que declaramos como públicas — e falha se algo a mais estiver
aceitando conexão, ou se um ponto de entrada declarado parar de responder.

## Por que ele mora num repositório separado

A pergunta que este controle responde é *"isto está alcançável pela internet?"*.
Uma sonda que roda **dentro** da rede auditada não consegue respondê-la: o que
distingue os dois casos é o endereço de origem do pacote, não o teste em si.
Nossos executores de CI próprios rodam dentro dessa mesma rede, então o
workflow precisa de um runner hospedado pelo GitHub — um ponto de observação
genuinamente externo.

Ele fica aqui, separado e público, porque runners hospedados estão disponíveis
para repositórios públicos.

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
