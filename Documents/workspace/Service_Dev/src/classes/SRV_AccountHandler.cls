public class SRV_AccountHandler {
    
    /*Author : Appshark
     * Description: To update Market segment, Customer support level , TEchnical support email  
     *              and technical support phone on all child accounts from business accout.
     */
    public static void UpdateChilds(map<id, Account> mapOldAccounts, map<id, Account> mapNewAccounts)
    {
        try
        {
            Set<id> setMSAccountIDs = new set<Id>(); //AccountIds that need update in MarketSegment only
            Set<id> setAccountIDs = new set<Id>(); //AccountIds that need update in MarketSegment and Support Fields
            
            //Prepare set of accountIDs that need update for Child Accounts and Cases
            for (Account objAccount : mapNewAccounts.Values())
            {
                //Get the Old account object
                Account objOldAccount = mapOldAccounts.get(objAccount.Id);
                //Change in Market Segment only - to update cases
                If (objOldAccount.Market_Segment__c != objAccount.Market_Segment__c && objAccount.Market_Segment__c != null)
                    setMSAccountIDs.add(objAccount.Id);
                
                //Change in Market Segment or Support Fields - To update Child Accounts
                If (objOldAccount.Market_Segment__c != objAccount.Market_Segment__c ||
                    objOldAccount.Customer_Support_Level__c != objAccount.Customer_Support_Level__c ||
                    objOldAccount.Technical_Support_Email_Address__c != objAccount.Technical_Support_Email_Address__c ||
                    objOldAccount.Technical_Support_Phone_Number__c != objAccount.Technical_Support_Phone_Number__c)
                    setAccountIDs.add(objAccount.Id);
            }
            
            //Updates Market segment on all child accounts from the parent account
            list<Account> lstChildAccounts = New list<Account>();
            for(Account objAcc : [select id, ParentId, Market_Segment__c, Customer_Support_Level__c,
                                  Technical_Support_Email_Address__c,Technical_Support_Phone_Number__c
                                  from Account where ParentId != null and ParentId In : setAccountIDs])
            {
                objAcc.Market_Segment__c = mapNewAccounts.get(objAcc.ParentId).Market_Segment__c;
                objAcc.Customer_Support_Level__c = mapNewAccounts.get(objAcc.ParentId).Customer_Support_Level__c;
                objAcc.Technical_Support_Email_Address__c = mapNewAccounts.get(objAcc.ParentId).Technical_Support_Email_Address__c;
                objAcc.Technical_Support_Phone_Number__c = mapNewAccounts.get(objAcc.ParentId).Technical_Support_Phone_Number__c;
                lstChildAccounts.add(objAcc);
            }
            if(!lstChildAccounts.isempty())
                update lstChildAccounts;
            
            //Updates Market segment on all open cases from the parent account
            list<Case> lstChildCases = New list<Case>();
            for(Case objCase : [select id,Market_Segment__c, AccountId from Case 
                                where AccountId In : setMSAccountIDs and status != 'Closed'])
            {
                objCase.Market_Segment__c  = mapNewAccounts.get(objCase.AccountId).Market_Segment__c;
                lstChildCases.add(objCase); 
            }
            if(!lstChildCases.isempty())
                update lstChildCases;
        }catch (exception ex)
        {
            throw new ApexException('Exception in Updating Child accounts and Cases:' +Ex.getMessage()); 
        }
    }
    public class ApexException extends Exception {}
}