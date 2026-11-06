<?php
// Executed only inside the disposable GLPI lab; never accepts an external database.
if (getenv('GLPI_LAB_CONFIRM') !== 'isolated-synthetic' || getenv('MARIADB_DATABASE') !== 'branef_glpi_lab') {
    throw new RuntimeException('Refusing non-laboratory target');
}
define('GLPI_ROOT', '/var/www/glpi');
require GLPI_ROOT . '/inc/includes.php';
if (GLPI_VERSION !== '10.0.18' || $DB->dbdefault !== 'branef_glpi_lab') {
    throw new RuntimeException('Wrong GLPI version or database');
}
function row($table, $where) {
    global $DB;
    foreach ($DB->request(['FROM' => $table, 'WHERE' => $where]) as $item) {
        return $item;
    }
    throw new RuntimeException('Required synthetic fixture not found');
}
function insert($table, $values) {
    global $DB;
    if (!$DB->insert($table, $values)) {
        throw new RuntimeException('Synthetic fixture insert failed');
    }
    return (int) $DB->insertId();
}
$now = date('Y-m-d H:i:s');
$profile = row('glpi_profiles', ['name' => 'Super-Admin']);
$technicalToken = bin2hex(random_bytes(20));
$limitedToken = bin2hex(random_bytes(20));
$appToken = bin2hex(random_bytes(20));
foreach (['enable_api', 'enable_api_login_external_token'] as $name) {
    $DB->update('glpi_configs', ['value' => '1'], ['context' => 'core', 'name' => $name]);
}
$DB->update('glpi_configs', ['value' => '0'], ['context' => 'core', 'name' => 'enable_api_login_credentials']);
insert('glpi_apiclients', ['name' => 'BRANEF synthetic lab', 'is_active' => 1, 'entities_id' => 0,
    'is_recursive' => 1, 'app_token' => $appToken, 'dolog_method' => 0]);
$technical = insert('glpi_users', ['name' => 'branef_lab_technical_' . bin2hex(random_bytes(4)), 'is_active' => 1,
    'profiles_id' => $profile['id'], 'entities_id' => 0, 'api_token' => $technicalToken, 'authtype' => 1]);
insert('glpi_profiles_users', ['users_id' => $technical, 'profiles_id' => $profile['id'], 'entities_id' => 0,
    'is_recursive' => 1, 'is_default_profile' => 1]);
$limitedProfile = $profile;
unset($limitedProfile['id']);
$limitedProfile['name'] = 'BRANEF synthetic limited ' . bin2hex(random_bytes(4));
$limitedProfile['is_default'] = 0;
$limitedProfileId = insert('glpi_profiles', $limitedProfile);
foreach ($DB->request(['FROM' => 'glpi_profilerights', 'WHERE' => ['profiles_id' => $profile['id']]]) as $right) {
    unset($right['id']);
    $right['profiles_id'] = $limitedProfileId;
    $right['rights'] = $right['name'] === 'ticket' ? 1 : 0;
    insert('glpi_profilerights', $right);
}
$limited = insert('glpi_users', ['name' => 'branef_lab_limited_' . bin2hex(random_bytes(4)), 'is_active' => 1,
    'profiles_id' => $limitedProfileId, 'entities_id' => 0, 'api_token' => $limitedToken, 'authtype' => 1]);
insert('glpi_profiles_users', ['users_id' => $limited, 'profiles_id' => $limitedProfileId, 'entities_id' => 0,
    'is_recursive' => 1, 'is_default_profile' => 1]);
$_SESSION['glpiID'] = $technical;
$_SESSION['glpi_currenttime'] = $now;
$_SESSION['glpi_use_mode'] = 0;
$_SESSION['glpilanguage'] = 'en_GB';
$_SESSION['glpiactiveprofile'] = $profile;
foreach ($DB->request(['FROM' => 'glpi_profilerights', 'WHERE' => ['profiles_id' => $profile['id']]]) as $right) {
    $_SESSION['glpiactiveprofile'][$right['name']] = $right['rights'];
}
$_SESSION['glpiactive_entity'] = 0;
$_SESSION['glpiactive_entity_recursive'] = true;
$_SESSION['glpiactiveentities'] = [0];
$_SESSION['glpiactiveentities_string'] = '0';
$entity = new Entity();
$support = (int) $entity->add(['name' => 'BRANEF LAB SUPPORT', 'entities_id' => 0]);
$child = (int) $entity->add(['name' => 'BRANEF LAB CHILD', 'entities_id' => $support]);
$foreign = (int) $entity->add(['name' => 'BRANEF LAB FOREIGN', 'entities_id' => 0]);
if (!$support || !$child || !$foreign) {
    throw new RuntimeException('Synthetic entity setup failed');
}
$narrowToken = bin2hex(random_bytes(20));
$narrow = insert('glpi_users', ['name' => 'branef_lab_narrow_' . bin2hex(random_bytes(4)), 'is_active' => 1,
    'profiles_id' => $profile['id'], 'entities_id' => $support, 'api_token' => $narrowToken, 'authtype' => 1]);
insert('glpi_profiles_users', ['users_id' => $narrow, 'profiles_id' => $profile['id'], 'entities_id' => 0,
    'is_recursive' => 1, 'is_default_profile' => 1]);
$tickets = [];
foreach (['root' => 0, 'support' => $support, 'child' => $child, 'foreign' => $foreign, 'limited_own' => 0] as $label => $entityId) {
    $requester = $label === 'limited_own' ? $limited : $technical;
    $tickets[$label] = insert('glpi_tickets', ['name' => 'SYNTHETIC BRANEF ' . $label, 'content' => '<p>Synthetic fixture</p>',
        'entities_id' => $entityId, 'type' => 1, 'status' => 1, 'priority' => 3, 'urgency' => 3, 'impact' => 3,
        'date' => $now, 'date_mod' => $now, 'users_id_recipient' => $requester]);
    insert('glpi_tickets_users', ['tickets_id' => $tickets[$label], 'users_id' => $requester, 'type' => 1]);
}
for ($index = 1; $index <= 205; $index++) {
    insert('glpi_itilfollowups', ['itemtype' => 'Ticket', 'items_id' => $tickets['root'], 'date' => $now,
        'users_id' => $technical, 'content' => 'Synthetic followup ' . $index, 'is_private' => $index === 205 ? 1 : 0]);
    insert('glpi_tickettasks', ['tickets_id' => $tickets['root'], 'date' => $now, 'date_mod' => $now,
        'users_id' => $technical, 'content' => 'Synthetic task ' . $index, 'is_private' => $index === 205 ? 1 : 0,
        'actiontime' => 60, 'state' => 1]);
}
$catalogues = [
    'group' => insert('glpi_groups', ['name' => 'BRANEF LAB GROUP', 'entities_id' => 0, 'is_recursive' => 1,
        'is_assign' => 1, 'is_requester' => 1, 'is_task' => 1]),
    'supplier' => insert('glpi_suppliers', ['name' => 'BRANEF LAB SUPPLIER', 'entities_id' => 0, 'is_recursive' => 1]),
    'computer' => insert('glpi_computers', ['name' => 'BRANEF LAB COMPUTER', 'entities_id' => 0]),
    'task_category' => insert('glpi_taskcategories', ['name' => 'BRANEF LAB TASK', 'entities_id' => 0, 'is_recursive' => 1]),
    'solution_type' => insert('glpi_solutiontypes', ['name' => 'BRANEF LAB SOLUTION', 'entities_id' => 0, 'is_recursive' => 1])
];
insert('glpi_groups_users', ['groups_id' => $catalogues['group'], 'users_id' => $technical, 'is_manager' => 1]);
$fixtures = ['version' => GLPI_VERSION, 'technical_user_id' => $technical, 'limited_user_id' => $limited,
    'entities' => ['root' => 0, 'support' => $support, 'child' => $child, 'foreign' => $foreign], 'tickets' => $tickets, 'catalogues' => $catalogues,
    'app_token' => $appToken, 'user_token' => $technicalToken, 'limited_token' => $limitedToken,
    'narrow_token' => $narrowToken, 'narrow_user_id' => $narrow];
require '/usr/local/lib/branef-glpi-template-fixtures.php';
$intakeSlm = insert('glpi_slms', ['name' => 'SYNTHETIC INTAKE SLM', 'entities_id' => 0,
    'is_recursive' => 1, 'use_ticket_calendar' => 0, 'calendars_id' => 0]);
$fixtures['intake'] = [
    'requester_id' => $limited,
    'group_id' => $catalogues['group'],
    'category_id' => insert('glpi_itilcategories', ['name' => 'SYNTHETIC INTAKE CATEGORY', 'entities_id' => 0,
        'is_recursive' => 1, 'is_incident' => 1, 'is_request' => 1, 'is_helpdeskvisible' => 1]),
    'sla_id' => insert('glpi_slas', ['name' => 'SYNTHETIC INTAKE FIVE DAYS', 'entities_id' => 0,
        'slms_id' => $intakeSlm, 'is_recursive' => 1, 'type' => 0, 'number_time' => 5,
        'definition_time' => 'day', 'end_of_working_day' => 0, 'use_ticket_calendar' => 0, 'calendars_id' => 0])
];
$path = '/lab-out/fixtures.json';
file_put_contents($path, json_encode($fixtures, JSON_THROW_ON_ERROR));
chmod($path, 0600);
chown($path, (int) getenv('LAB_HOST_UID'));
echo json_encode(['version' => GLPI_VERSION, 'entities' => $fixtures['entities'], 'ticket_count' => count($tickets)]) . PHP_EOL;
