#!/bin/bash
# =============================================================================
# register-ues.sh — Provisionnement direct MongoDB pour 7 UEs
# SD corrigé : 001083 (correspond au SMF/AMF config)
# =============================================================================
PLMN="20893"
K="00112233445566778899aabbccddeeff"
OPC="63bfa50ee6523365ff14c1f45f88737d"
SD="001083"

echo "[INFO] Provisionnement des abonnés via MongoDB..."

mongosh free5gc --quiet --eval "
var PLMN = '${PLMN}';
var K    = '${K}';
var OPC  = '${OPC}';
var SD   = '001083';

// UE1, UE2, UE3, UE6, UE7 enregistrés (credentials corrects en base)
// UE4 : NON enregistré -> Registration Reject
// UE5 : même IMSI que UE1 -> conflit session
var subscribers = [
  { imsi: 'imsi-208930123456781', msisdn: 'msisdn-0900000101' },
  { imsi: 'imsi-208930123456782', msisdn: 'msisdn-0900000102' },
  { imsi: 'imsi-208930123456783', msisdn: 'msisdn-0900000103' },
  { imsi: 'imsi-208930123456786', msisdn: 'msisdn-0900000106' },
  { imsi: 'imsi-208930123456787', msisdn: 'msisdn-0900000107' }
];

subscribers.forEach(function(sub) {
  var ueId = sub.imsi;

  db['subscriptionData.authenticationData.authenticationSubscription'].replaceOne(
    { ueId: ueId },
    {
      ueId: ueId,
      authenticationMethod: '5G_AKA',
      encPermanentKey: K,
      encOpcKey: OPC,
      authenticationManagementField: '8000',
      sequenceNumber: { sqnScheme: 'GENERAL', sqn: '000000000000', lastCounters: [] }
    }, { upsert: true });

  db['subscriptionData.authenticationData.webAuthenticationSubscription'].replaceOne(
    { ueId: ueId },
    {
      ueId: ueId,
      authenticationMethod: '5G_AKA',
      permanentKey: { permanentKeyValue: K, encryptionKey: 0, encryptionAlgorithm: 0 },
      opc: { opcValue: OPC.toUpperCase(), encryptionKey: 0, encryptionAlgorithm: 0 },
      milenage: { op: { opValue: '', encryptionKey: 0, encryptionAlgorithm: 0 } },
      authenticationManagementField: '8000',
      sequenceNumber: { sqnScheme: 'GENERAL', sqn: '000000000000', lastCounters: [] }
    }, { upsert: true });

  db['subscriptionData.provisionedData.amData'].replaceOne(
    { ueId: ueId, servingPlmnId: PLMN },
    {
      ueId: ueId, servingPlmnId: PLMN,
      gpsis: [ sub.msisdn ],
      subscribedUeAmbr: { uplink: '1 Gbps', downlink: '2 Gbps' },
      nssai: {
        defaultSingleNssais: [{ sst: 1, sd: SD }],
        singleNssais: []
      }
    }, { upsert: true });

  db['subscriptionData.provisionedData.smData'].replaceOne(
    { ueId: ueId, servingPlmnId: PLMN },
    {
      ueId: ueId, servingPlmnId: PLMN,
      singleNssai: { sst: 1, sd: SD },
      dnnConfigurations: {
        internet: {
          pduSessionTypes:  { defaultSessionType: 'IPV4', allowedSessionTypes: ['IPV4'] },
          sscModes:         { defaultSscMode: 'SSC_MODE_1', allowedSscModes: ['SSC_MODE_2','SSC_MODE_3'] },
          '5gQosProfile':   { '5qi': 9, arp: { priorityLevel: 8, preemptCap: 'NOT_PREEMPT', preemptVuln: 'NOT_PREEMPTABLE' }, priorityLevel: 8 },
          sessionAmbr:      { uplink: '200 Mbps', downlink: '100 Mbps' }
        }
      }
    }, { upsert: true });

  db['subscriptionData.provisionedData.smfSelectionSubscriptionData'].replaceOne(
    { ueId: ueId, servingPlmnId: PLMN },
    {
      ueId: ueId, servingPlmnId: PLMN,
      subscribedSnssaiInfos: {
        ['01' + SD]: {
          snssai: { sst: 1, sd: SD },
          dnnInfos: [{ dnn: 'internet' }]
        }
      }
    }, { upsert: true });

  db['subscriptionData.identityData'].replaceOne(
    { ueId: ueId },
    { ueId: ueId, gpsi: sub.msisdn },
    { upsert: true });

  db['policyData.ues.amData'].replaceOne(
    { ueId: ueId }, { ueId: ueId }, { upsert: true });

  db['policyData.ues.smData'].replaceOne(
    { ueId: ueId },
    {
      ueId: ueId,
      smPolicySnssaiData: { ['01' + SD]: {
        snssai: { sst: 1, sd: SD },
        smPolicyDnnData: { internet: {
          dnn: 'internet',
          sscModes: { defaultSscMode: 'SSC_MODE_1', allowedSscModes: ['SSC_MODE_2','SSC_MODE_3'] },
          pduSessionTypes: { defaultSessionType: 'IPV4', allowedSessionTypes: ['IPV4'] }
        }}
      }}
    }, { upsert: true });

  print('  [OK] ' + ueId);
});

print('');
print('[OK] ' + subscribers.length + ' abonnés provisionnés (SD=' + SD + ')');
print('  UE4 (imsi-208930123456785) : NON enregistré -> Registration Reject');
print('  UE5 (imsi-208930123456781) : même IMSI que UE1 -> Conflit session');
" 2>/dev/null

# Reset SQN pour éviter les SQN mismatch lors des relances
mongosh free5gc --quiet --eval "
db['subscriptionData.authenticationData.authenticationSubscription'].updateMany(
  { ueId: { \$regex: '^imsi-20893012345678' } },
  { \$set: { 'sequenceNumber.sqn': '000000000000', 'sequenceNumber.lastCounters': [] } }
);
print('[OK] SQN remis à zéro');" 2>/dev/null

echo "[OK] Provisionnement terminé"
