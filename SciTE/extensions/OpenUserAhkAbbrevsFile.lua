-- �˵��� - ѡ�� - �� �û������ﶨ���ļ� ָ���·�����ԣ��������������������
function OpenUserAhkAbbrevsFile()
	local SciteUserHome = props["SciteUserHome"]
	local user_ahk_abbrevs_path = SciteUserHome.."/user.ahk.abbrevs.properties"
	scite.Open(user_ahk_abbrevs_path)
end