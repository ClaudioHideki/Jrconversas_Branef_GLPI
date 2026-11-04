<?php
// Included only after bootstrap.php verifies the isolated GLPI version/database.
$parent = (int) $entity->add(['name' => 'BRANEF LAB TEMPLATE PARENT', 'entities_id' => 0]);
$descendant = (int) $entity->add(['name' => 'BRANEF LAB TEMPLATE CHILD', 'entities_id' => $parent]);
if (!$parent || !$descendant) {
    throw new RuntimeException('Synthetic template entities failed');
}
$models = [];
foreach (['entity', 'profile', 'incident', 'request', 'explicit', 'unsupported', 'redirect'] as $label) {
    $models[$label] = insert('glpi_tickettemplates', ['name' => 'SYNTHETIC MODEL ' . $label,
        'entities_id' => $parent, 'is_recursive' => 1]);
}
$models['foreign'] = insert('glpi_tickettemplates', ['name' => 'SYNTHETIC FOREIGN MODEL',
    'entities_id' => $foreign, 'is_recursive' => 0]);
$category = insert('glpi_itilcategories', ['name' => 'SYNTHETIC TYPED MODEL CATEGORY', 'entities_id' => $parent,
    'is_recursive' => 1, 'is_incident' => 1, 'is_request' => 1,
    'tickettemplates_id_incident' => $models['incident'], 'tickettemplates_id_demand' => $models['request']]);
$ticket = new Ticket();
$numbers = [];
foreach (['name', 'content', 'type', 'urgency', 'impact', 'priority'] as $field) {
    $numbers[$field] = $ticket->getSearchOptionIDByField('field', $field, 'glpi_tickets');
}
$numbers['category'] = $ticket->getSearchOptionIDByField('field', 'completename', 'glpi_itilcategories');
$numbers['requesttype'] = $ticket->getSearchOptionIDByField('field', 'name', 'glpi_requesttypes');
foreach ($numbers as $number) {
    if (!is_numeric($number) || (int) $number <= 0) {
        throw new RuntimeException('Official template search option missing');
    }
}
$predefined = [];
foreach (['entity' => 4, 'profile' => 5, 'incident' => 2, 'request' => 1, 'explicit' => 4] as $label => $urgency) {
    $predefined[$label . '_name'] = insert('glpi_tickettemplatepredefinedfields', ['tickettemplates_id' => $models[$label],
        'num' => $numbers['name'], 'value' => 'SYNTHETIC MODEL TITLE ' . $label]);
    $predefined[$label . '_urgency'] = insert('glpi_tickettemplatepredefinedfields', ['tickettemplates_id' => $models[$label],
        'num' => $numbers['urgency'], 'value' => (string) $urgency]);
}
insert('glpi_tickettemplatepredefinedfields', ['tickettemplates_id' => $models['explicit'],
    'num' => $numbers['content'], 'value' => '<p>Describe the synthetic issue</p>']);
insert('glpi_tickettemplatepredefinedfields', ['tickettemplates_id' => $models['explicit'],
    'num' => $numbers['impact'], 'value' => '2']);
insert('glpi_tickettemplatehiddenfields', ['tickettemplates_id' => $models['explicit'], 'num' => $numbers['urgency']]);
foreach ([$numbers['content'], 4] as $number) {
    insert('glpi_tickettemplatemandatoryfields', ['tickettemplates_id' => $models['explicit'], 'num' => $number]);
}
insert('glpi_tickettemplatemandatoryfields', ['tickettemplates_id' => $models['unsupported'], 'num' => $numbers['requesttype']]);
// Category-selected models must ignore their own type/category selectors.
foreach ([$numbers['type'] => '2', $numbers['category'] => (string) $category] as $number => $value) {
    insert('glpi_tickettemplatepredefinedfields', ['tickettemplates_id' => $models['incident'], 'num' => $number, 'value' => $value]);
    insert('glpi_tickettemplatehiddenfields', ['tickettemplates_id' => $models['incident'], 'num' => $number]);
    insert('glpi_tickettemplatepredefinedfields', ['tickettemplates_id' => $models['redirect'], 'num' => $number, 'value' => $value]);
}
$DB->update('glpi_entities', ['tickettemplates_strategy' => 1, 'tickettemplates_id' => $models['entity'], 'tickettype' => 2], ['id' => $parent]);
$DB->update('glpi_entities', ['tickettemplates_strategy' => -2, 'tickettype' => -2], ['id' => $descendant]);
$users = [];
foreach (['base' => 0, 'profile' => $models['profile'], 'redirect' => $models['redirect'], 'denied' => 0] as $label => $model) {
    $copy = $profile;
    unset($copy['id']);
    $copy['name'] = 'SYNTHETIC TEMPLATE PROFILE ' . $label;
    $copy['is_default'] = 0;
    $copy['tickettemplates_id'] = $model;
    $profileId = insert('glpi_profiles', $copy);
    foreach ($DB->request(['FROM' => 'glpi_profilerights', 'WHERE' => ['profiles_id' => $profile['id']]]) as $right) {
        unset($right['id']);
        $right['profiles_id'] = $profileId;
        if ($label === 'denied' && $right['name'] === 'itiltemplate') {
            $right['rights'] = 0;
        }
        insert('glpi_profilerights', $right);
    }
    $token = bin2hex(random_bytes(20));
    $user = insert('glpi_users', ['name' => 'branef_lab_template_' . $label, 'is_active' => 1,
        'profiles_id' => $profileId, 'entities_id' => $parent, 'api_token' => $token, 'authtype' => 1]);
    insert('glpi_profiles_users', ['users_id' => $user, 'profiles_id' => $profileId, 'entities_id' => 0,
        'is_recursive' => 1, 'is_default_profile' => 1]);
    $users[$label] = ['id' => $user, 'token' => $token];
}
$fixtures['templates'] = ['entities' => ['parent' => $parent, 'child' => $descendant], 'models' => $models,
    'category_id' => $category, 'users' => $users, 'predefined_ids' => $predefined];
